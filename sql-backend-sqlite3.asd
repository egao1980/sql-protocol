(defsystem "sql-backend-sqlite3"
  :version "0.1.0"
  :description "sql-protocol backend — SQLite3 via cl-dbi (dbd-sqlite3); default driver"
  :author "egao1980"
  :license "MIT"
  :depends-on ("sql-protocol" "dbd-sqlite3")
  :serial t
  :pathname "src/backend-sqlite3"
  :components ((:file "package")
               (:file "backend")))
