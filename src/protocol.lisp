(in-package #:sql-protocol)

;;; Soft cl-dbi calls — dbi is provided by backends (dbd-*), not a hard dep of
;;; sql-protocol itself.

(defun %dbi-package ()
  (or (find-package :dbi)
      (error 'sql-programming-error
             :message "cl-dbi is not loaded — load sql-backend-sqlite3 or sql-backend-postgres")))

(defun %dbi-symbol (name)
  (or (find-symbol (string name) (%dbi-package))
      (error 'sql-programming-error
             :message (format nil "dbi symbol ~a not found" name))))

(defun %dbi-call (name &rest args)
  (apply (%dbi-symbol name) args))

(defun %dbi-type-p (object type-name)
  (let* ((pkg (or (find-package :dbi.error) (find-package :dbi)))
         (sym (and pkg (find-symbol (string type-name) pkg)))
         (class (and sym (find-class sym nil))))
    (and class (typep object class))))

(defun %condition-message (c)
  (or (ignore-errors
        (let ((reader (find-symbol "DATABASE-ERROR-MESSAGE" :dbi.error)))
          (when (and reader (fboundp reader))
            (funcall reader c))))
      (princ-to-string c)))

(defun %signal-mapped-dbi-error (c)
  (let ((msg (%condition-message c)))
    (cond
      ((%dbi-type-p c "DBI-INTEGRITY-ERROR")
       (error 'sql-integrity-error :message msg))
      ((%dbi-type-p c "DBI-PROGRAMMING-ERROR")
       (error 'sql-programming-error :message msg))
      ((%dbi-type-p c "DBI-OPERATIONAL-ERROR")
       (error 'sql-operational-error :message msg))
      ((%dbi-type-p c "DBI-DATABASE-ERROR")
       (error 'sql-operational-error :message msg))
      ((%dbi-type-p c "DBI-ERROR")
       (error 'sql-error :message msg))
      (t (error c)))))

(defmacro with-sql-errors (&body body)
  `(handler-bind ((error
                   (lambda (c)
                     (when (%dbi-type-p c "DBI-ERROR")
                       (%signal-mapped-dbi-error c)))))
     ,@body))

;;; ---------------------------------------------------------------------------
;;; Classes / specials
;;; ---------------------------------------------------------------------------

(defclass sql-backend () ()
  (:documentation "Base class for sql-protocol driver backends."))

(defclass sql-connection ()
  ((raw :initarg :raw :reader raw-connection
        :documentation "Underlying cl-dbi connection object."))
  (:documentation "Stack SQL connection wrapping a cl-dbi connection."))

(defclass sql-result ()
  ((raw-query :initarg :raw-query :reader raw-query
              :documentation "Underlying cl-dbi query / execute result."))
  (:documentation "Result cursor wrapping a cl-dbi query."))

(defvar *sql-backend* nil
  "Default sql-backend instance (set by backends via use-*-backend).")

(defvar *sql-connection* nil
  "Dynamically bound current sql-connection.")

(defvar *sql-driver-backends* (make-hash-table :test #'eq)
  "Map of driver keyword (:sqlite3, :postgres, …) → sql-backend instance.")

(defun register-sql-backend (driver backend)
  "Register BACKEND for DRIVER keyword used by CONNECT. Returns BACKEND."
  (check-type driver keyword)
  (check-type backend sql-backend)
  (setf (gethash driver *sql-driver-backends*) backend))

;;; ---------------------------------------------------------------------------
;;; Generics
;;; ---------------------------------------------------------------------------

(defgeneric backend-connect (backend &key database-name host port username password options
                                     &allow-other-keys)
  (:documentation "Open a sql-connection via BACKEND."))

(defgeneric disconnect (connection)
  (:documentation "Close CONNECTION."))

(defgeneric ping (connection)
  (:documentation "Return true when CONNECTION is alive."))

(defgeneric execute (connection sql &optional params)
  (:documentation "Execute SQL string with optional PARAMS list. Returns sql-result.
   Query AST objects belong to sql-query, not this layer."))

(defgeneric fetch (result &key)
  (:documentation "Fetch next row as plist, or NIL when exhausted."))

(defgeneric fetch-all (result &key)
  (:documentation "Fetch remaining rows as a list of plists."))

;;; ---------------------------------------------------------------------------
;;; Default methods (cl-dbi)
;;; ---------------------------------------------------------------------------

(defmethod disconnect ((connection sql-connection))
  (let ((raw (raw-connection connection)))
    (when raw
      (with-sql-errors
        (%dbi-call "DISCONNECT" raw))))
  (values))

(defun %ping-select-1 (connection)
  (let ((result (execute connection "SELECT 1")))
    (and (fetch result) t)))

(defmethod ping ((connection sql-connection))
  (let ((raw (raw-connection connection)))
    (unless raw
      (return-from ping nil))
    (with-sql-errors
      (handler-case
          (let ((ping-fn (ignore-errors (%dbi-symbol "PING"))))
            (if ping-fn
                (handler-case (funcall ping-fn raw)
                  ;; Some drivers signal notsupported — fall through to SELECT 1.
                  (error () (%ping-select-1 connection)))
                (%ping-select-1 connection)))
        (sql-error () nil)
        (error () nil)))))

(defmethod execute ((connection sql-connection) sql &optional params)
  (check-type sql string)
  (with-sql-errors
    (let* ((raw (or (raw-connection connection)
                    (error 'sql-connection-error :message "connection has no raw dbi handle")))
           (query (%dbi-call "PREPARE" raw sql))
           (executed (%dbi-call "EXECUTE" query (or params nil))))
      (make-instance 'sql-result :raw-query executed))))

(defun %normalize-row (row)
  "Upcase plist keys so GETF with :id works (cl-dbi interns raw column names)."
  (when row
    (loop for (k v) on row by #'cddr
          collect (intern (string-upcase (string k)) :keyword)
          collect v)))

(defmethod fetch ((result sql-result) &key (format :plist))
  (with-sql-errors
    (let ((row (%dbi-call "FETCH" (raw-query result) :format format)))
      (if (eq format :plist)
          (%normalize-row row)
          row))))

(defmethod fetch-all ((result sql-result) &key (format :plist))
  (with-sql-errors
    (let ((rows (%dbi-call "FETCH-ALL" (raw-query result) :format format)))
      (if (eq format :plist)
          (mapcar #'%normalize-row rows)
          rows))))

;;; ---------------------------------------------------------------------------
;;; DX: connect / with-connection / with-transaction
;;; ---------------------------------------------------------------------------

(defun connect (&rest keys &key (driver :sqlite3) &allow-other-keys)
  "Connect using DRIVER (:sqlite3 or :postgres) and backend kwargs.
   Requires the matching sql-backend-* system to be loaded (and registered)."
  (let* ((keys (copy-list keys))
         (backend (or (gethash driver *sql-driver-backends*)
                      (and *sql-backend*
                           (eq driver :sqlite3)
                           *sql-backend*)
                      (error 'sql-connection-error
                             :message
                             (format nil
                                     "no backend registered for driver ~s — load sql-backend-~(~a~)"
                                     driver driver)))))
    (remf keys :driver)
    (apply #'backend-connect backend keys)))

(defmacro with-connection ((var &rest keys) &body body)
  "Connect, bind VAR (and *SQL-CONNECTION*), disconnect on unwind."
  (let ((conn (gensym "CONN")))
    `(let* ((,conn (connect ,@keys))
            (,var ,conn)
            (*sql-connection* ,conn))
       (unwind-protect
            (progn ,@body)
         (ignore-errors (disconnect ,conn))))))

(defun call-with-transaction (connection thunk)
  "Run THUNK inside a DB transaction on CONNECTION.
   Uses dbi:begin-transaction plus do-sql COMMIT/ROLLBACK so we do not depend
   on dbi:with-transaction's dynamic state (dbi:commit :around is a no-op
   outside that macro)."
  (let ((raw (or (raw-connection connection)
                 (error 'sql-connection-error :message "connection has no raw dbi handle")))
        (ok nil))
    (with-sql-errors
      (%dbi-call "BEGIN-TRANSACTION" raw)
      (unwind-protect
           (multiple-value-prog1
               (funcall thunk)
             (setf ok t))
        (if ok
            (%dbi-call "DO-SQL" raw "COMMIT")
            (ignore-errors (%dbi-call "DO-SQL" raw "ROLLBACK")))))))

(defmacro with-transaction ((connection) &body body)
  "BEGIN/COMMIT via cl-dbi; ROLLBACK on non-local exit."
  `(call-with-transaction ,connection (lambda () ,@body)))