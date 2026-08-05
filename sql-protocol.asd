(defsystem "sql-protocol"
  :version "0.1.0"
  :description "CLOS SQL connectivity protocol for cl-stack (Engine/Pool/DB-API; no query DSL)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("uiop" "bordeaux-threads")
  :serial t
  :pathname "src"
  :components ((:file "package")
               (:file "conditions")
               (:file "protocol")
               (:file "pool"))
  :in-order-to ((test-op (test-op "sql-protocol/tests"))))

(defsystem "sql-protocol/tests"
  :depends-on ("sql-protocol" "sql-backend-sqlite3" "rove")
  :pathname "tests"
  :serial t
  :components ((:file "package")
               (:file "sql-test"))
  :perform (test-op (o c)
             (unless (symbol-call :rove :run c)
               (error "tests failed for ~A" (component-name c)))))
