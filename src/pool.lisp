(in-package #:sql-protocol)

;;; Wave-1 pool: BT lock + free list; max connections; timed wait on checkout.

(defclass sql-pool ()
  ((backend :initarg :backend :reader pool-backend)
   (min :initarg :min :reader pool-min :initform 0)
   (max :initarg :max :reader pool-max :initform 4)
   (timeout :initarg :timeout :reader pool-timeout :initform 5.0)
   (connect-args :initarg :connect-args :reader pool-connect-args :initform nil)
   (lock :initform (bt2:make-lock :name "sql-pool") :reader pool-lock)
   (cv :initform (bt2:make-condition-variable :name "sql-pool") :reader pool-cv)
   (free :initform nil :accessor pool-free)
   (size :initform 0 :accessor pool-size)
   (shutdown-p :initform nil :accessor pool-shutdown-p)))

(defgeneric make-pool (backend &key min max timeout &allow-other-keys)
  (:documentation "Create a connection pool for BACKEND."))

(defgeneric pool-connect (pool)
  (:documentation "Checkout a sql-connection from POOL."))

(defgeneric pool-release (pool connection)
  (:documentation "Return CONNECTION to POOL (or disconnect if shut down)."))

(defmethod make-pool ((backend sql-backend) &rest connect-args
                      &key (min 0) (max 4) (timeout 5.0)
                      &allow-other-keys)
  (let ((args (copy-list connect-args)))
    (remf args :min)
    (remf args :max)
    (remf args :timeout)
    (let ((pool (make-instance 'sql-pool
                               :backend backend
                               :min min
                               :max max
                               :timeout timeout
                               :connect-args args)))
      (bt2:with-lock-held ((pool-lock pool))
        (dotimes (i (pool-min pool))
          (push (apply #'backend-connect (pool-backend pool) (pool-connect-args pool))
                (pool-free pool))
          (incf (pool-size pool))))
      pool)))

(defun %pool-create-connection (pool)
  (apply #'backend-connect (pool-backend pool) (pool-connect-args pool)))

(defmethod pool-connect ((pool sql-pool))
  (let ((deadline (+ (get-internal-real-time)
                     (floor (* (pool-timeout pool) internal-time-units-per-second)))))
    (loop
      (let ((checkout nil)
            (create-p nil))
        (bt2:with-lock-held ((pool-lock pool))
          (when (pool-shutdown-p pool)
            (error 'sql-pool-timeout :message "pool is shut down"))
          (cond
            ((pool-free pool)
             (setf checkout (pop (pool-free pool))))
            ((< (pool-size pool) (pool-max pool))
             (incf (pool-size pool))
             (setf create-p t))
            (t
             (let* ((now (get-internal-real-time))
                    (remaining (/ (- deadline now) internal-time-units-per-second)))
               (when (<= remaining 0)
                 (error 'sql-pool-timeout
                        :message (format nil "pool checkout timed out after ~as"
                                         (pool-timeout pool))))
               (unless (bt2:condition-wait (pool-cv pool) (pool-lock pool)
                                           :timeout remaining)
                 (error 'sql-pool-timeout
                        :message (format nil "pool checkout timed out after ~as"
                                         (pool-timeout pool))))))))
        (when checkout
          (return-from pool-connect checkout))
        (when create-p
          (return-from pool-connect
            (handler-case (%pool-create-connection pool)
              (error (e)
                (bt2:with-lock-held ((pool-lock pool))
                  (decf (pool-size pool)))
                (error e)))))))))

(defmethod pool-release ((pool sql-pool) (connection sql-connection))
  (bt2:with-lock-held ((pool-lock pool))
    (cond
      ((pool-shutdown-p pool)
       (ignore-errors (disconnect connection))
       (when (plusp (pool-size pool))
         (decf (pool-size pool))))
      (t
       (push connection (pool-free pool))
       (bt2:condition-notify (pool-cv pool)))))
  (values))

(defun shutdown-pool (pool)
  "Mark POOL shut down; disconnect free connections. In-flight connections
   are disconnected on pool-release."
  (bt2:with-lock-held ((pool-lock pool))
    (setf (pool-shutdown-p pool) t)
    (dolist (c (pool-free pool))
      (ignore-errors (disconnect c))
      (when (plusp (pool-size pool))
        (decf (pool-size pool))))
    (setf (pool-free pool) nil)
    (bt2:condition-notify (pool-cv pool)))
  (values))

(defmacro with-pool-connection ((var pool) &body body)
  "Checkout from POOL, bind VAR, release on unwind."
  (let ((p (gensym "POOL"))
        (conn (gensym "CONN")))
    `(let* ((,p ,pool)
            (,conn (pool-connect ,p))
            (,var ,conn)
            (*sql-connection* ,conn))
       (unwind-protect
            (progn ,@body)
         (pool-release ,p ,conn)))))
