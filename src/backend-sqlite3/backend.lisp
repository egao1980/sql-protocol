(in-package #:sql-backend-sqlite3)

(defclass sqlite3-backend (sql-backend) ()
  (:documentation "SQLite3 backend via cl-dbi dbd-sqlite3."))

(defun make-sqlite3-backend ()
  (make-instance 'sqlite3-backend))

(defun %database-name (database-name)
  (etypecase database-name
    (null ":memory:")
    (string database-name)
    (pathname (uiop:native-namestring database-name))))

(defmethod backend-connect ((backend sqlite3-backend)
                            &key database-name host port username password options
                            &allow-other-keys)
  (declare (ignore host port username password options))
  (let ((name (%database-name database-name)))
    (handler-case
        (make-instance 'sql-connection
                       :raw (dbi:connect :sqlite3 :database-name name))
      (error (e)
        (if (sql-protocol::%dbi-type-p e "DBI-ERROR")
            (sql-protocol::%signal-mapped-dbi-error e)
            (error 'sql-connection-error
                   :message (format nil "sqlite3 connect failed: ~a" e)))))))

(defun use-sqlite3-backend ()
  "Bind *SQL-BACKEND* to a SQLite3 backend and register :sqlite3. Returns the backend."
  (let ((backend (make-sqlite3-backend)))
    (setf *sql-backend* backend)
    (register-sql-backend :sqlite3 backend)
    backend))

(use-sqlite3-backend)
