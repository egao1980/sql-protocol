(in-package #:sql-backend-postgres)

(defclass postgres-backend (sql-backend) ()
  (:documentation "PostgreSQL backend via cl-dbi dbd-postgres."))

(defun make-postgres-backend ()
  (make-instance 'postgres-backend))

(defmethod backend-connect ((backend postgres-backend)
                            &key database-name host port username password options
                            &allow-other-keys)
  (declare (ignore options))
  (handler-case
      (make-instance 'sql-connection
                     :raw (apply #'dbi:connect
                                 :postgres
                                 (append
                                  (when database-name (list :database-name database-name))
                                  (when host (list :host host))
                                  (when port (list :port port))
                                  (when username (list :username username))
                                  (when password (list :password password)))))
    (error (e)
      (if (sql-protocol::%dbi-type-p e "DBI-ERROR")
          (sql-protocol::%signal-mapped-dbi-error e)
          (error 'sql-connection-error
                 :message (format nil "postgres connect failed: ~a" e))))))

(defun use-postgres-backend ()
  "Register :postgres backend. Does NOT replace *SQL-BACKEND* (sqlite3 stays default)."
  (let ((backend (make-postgres-backend)))
    (register-sql-backend :postgres backend)
    backend))

;; Register on load so CONNECT :driver :postgres works without an extra call,
;; but leave *SQL-BACKEND* alone (do not auto-bind as default).
(register-sql-backend :postgres (make-postgres-backend))
