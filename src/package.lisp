(defpackage #:sql-protocol
  (:use #:cl)
  (:nicknames #:stack-sql)
  (:export #:sql-error
           #:sql-connection-error
           #:sql-programming-error
           #:sql-integrity-error
           #:sql-operational-error
           #:sql-pool-timeout
           #:sql-error-message

           #:sql-backend
           #:sql-connection
           #:raw-connection
           #:sql-pool
           #:sql-result
           #:raw-query

           #:*sql-backend*
           #:*sql-connection*
           #:*sql-driver-backends*

           #:backend-connect
           #:disconnect
           #:ping
           #:execute
           #:fetch
           #:fetch-all

           #:make-pool
           #:pool-connect
           #:pool-release
           #:shutdown-pool

           #:register-sql-backend
           #:connect
           #:with-connection
           #:with-transaction
           #:with-pool-connection))

(in-package #:sql-protocol)
