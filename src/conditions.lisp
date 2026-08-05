(in-package #:sql-protocol)

(define-condition sql-error (error)
  ((message :initarg :message :reader sql-error-message :initform nil))
  (:report (lambda (c s)
             (format s "SQL error~@[: ~a~]" (sql-error-message c)))))

(define-condition sql-connection-error (sql-error) ())
(define-condition sql-programming-error (sql-error) ())
(define-condition sql-integrity-error (sql-error) ())
(define-condition sql-operational-error (sql-error) ())
(define-condition sql-pool-timeout (sql-error) ())
