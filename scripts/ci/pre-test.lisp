;;; Load postgres backend before test-op when the live job is enabled.
(when (equal "1" (uiop:getenv "SQL_POSTGRES"))
  (dolist (n '("cl-postgres" "dbd-postgres" "sql-backend-postgres"))
    (asdf:load-system n :verbose nil)))
