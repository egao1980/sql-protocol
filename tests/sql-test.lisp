(in-package #:sql-protocol/tests)

(deftest sqlite-memory-crud
  (sql-protocol:with-connection (conn :driver :sqlite3 :database-name ":memory:")
    (sql-protocol:execute conn
                          "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
    (sql-protocol:execute conn "INSERT INTO users (name) VALUES (?)" '("ada"))
    (sql-protocol:execute conn "INSERT INTO users (name) VALUES (?)" '("grace"))
    (let* ((result (sql-protocol:execute conn "SELECT id, name FROM users ORDER BY id"))
           (rows (sql-protocol:fetch-all result)))
      (ok (= 2 (length rows)))
      (let ((first (first rows)))
        (ok (getf first :id))
        (ok (equal "ada" (getf first :name)))
        (ok (member :id first))
        (ok (member :name first))))))

(deftest with-transaction-rollback
  (sql-protocol:with-connection (conn :driver :sqlite3 :database-name ":memory:")
    (sql-protocol:execute conn
                          "CREATE TABLE items (id INTEGER PRIMARY KEY, label TEXT)")
    (handler-case
        (sql-protocol:with-transaction (conn)
          (sql-protocol:execute conn "INSERT INTO items (label) VALUES (?)" '("kept-not"))
          (error "boom"))
      (error ()))
    (let ((rows (sql-protocol:fetch-all
                 (sql-protocol:execute conn "SELECT label FROM items"))))
      (ok (null rows)))
    (sql-protocol:with-transaction (conn)
      (sql-protocol:execute conn "INSERT INTO items (label) VALUES (?)" '("ok")))
    (let ((row (sql-protocol:fetch
                (sql-protocol:execute conn "SELECT label FROM items"))))
      (ok (equal "ok" (getf row :label))))))

(deftest pool-checkout-release-and-timeout
  (let* ((backend sql-protocol:*sql-backend*)
         (pool (sql-protocol:make-pool backend
                                       :database-name ":memory:"
                                       :min 0
                                       :max 1
                                       :timeout 0.3)))
    (ok (not (null backend)))
    (let ((held (sql-protocol:pool-connect pool)))
      (ok (typep held 'sql-protocol:sql-connection))
      (sql-protocol:execute held "CREATE TABLE t (x INTEGER)")
      (sql-protocol:execute held "INSERT INTO t (x) VALUES (1)")
      ;; Pool exhausted — second checkout must time out while held.
      (ok (signals (sql-protocol:pool-connect pool)
                   'sql-protocol:sql-pool-timeout))
      (sql-protocol:pool-release pool held)
      ;; After release, checkout works again.
      (sql-protocol:with-pool-connection (c pool)
        (let ((row (sql-protocol:fetch
                    (sql-protocol:execute c "SELECT x FROM t"))))
          (ok (= 1 (getf row :x)))))
      (sql-protocol:shutdown-pool pool))))

(deftest postgres-skipped-unless-env
  ;; Ship postgres backend code; live tests need SQL_POSTGRES=1.
  (let ((enabled (equal "1" (uiop:getenv "SQL_POSTGRES"))))
    (if enabled
        (progn
          (asdf:load-system "sql-backend-postgres")
          (sql-protocol:with-connection
              (conn :driver :postgres
                    :database-name (or (uiop:getenv "SQL_POSTGRES_DB") "postgres")
                    :host (or (uiop:getenv "SQL_POSTGRES_HOST") "localhost")
                    :port (parse-integer (or (uiop:getenv "SQL_POSTGRES_PORT") "5432"))
                    :username (or (uiop:getenv "SQL_POSTGRES_USER") "postgres")
                    :password (or (uiop:getenv "SQL_POSTGRES_PASSWORD") "postgres"))
            (let ((row (sql-protocol:fetch
                        (sql-protocol:execute conn "SELECT 1 AS n"))))
              (ok (= 1 (getf row :n))))))
        (ok t "postgres tests skipped (set SQL_POSTGRES=1 to enable)"))))
