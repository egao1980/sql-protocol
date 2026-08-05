(defsystem "sql-backend-postgres"
  :version "0.1.0"
  :description "sql-protocol backend — PostgreSQL via cl-dbi (dbd-postgres)"
  :author "egao1980"
  :license "MIT"
  :depends-on ("sql-protocol" "dbd-postgres")
  :serial t
  :pathname "src/backend-postgres"
  :components ((:file "package")
               (:file "backend")))
