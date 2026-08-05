# sql-protocol

CLOS SQL **connectivity** layer for [cl-stack](https://github.com/egao1980/cl-stack) — Engine / Connection / Pool / DB-API shaped.

Does **not** include SxQL or Mito (those are `sql-query` / `sql-orm`).

| System | Role |
|--------|------|
| `sql-protocol` (`stack-sql`) | connect / execute / fetch / txn / pool |
| `sql-backend-sqlite3` | default driver (auto `use-sqlite3-backend`) |
| `sql-backend-postgres` | second driver (`use-postgres-backend`; not auto-default) |

## Quick use

```lisp
(asdf:load-system "sql-backend-sqlite3")

(stack-sql:with-connection (c :driver :sqlite3 :database-name ":memory:")
  (stack-sql:execute c "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
  (stack-sql:execute c "INSERT INTO t (name) VALUES (?)" '("ada"))
  (stack-sql:fetch-all (stack-sql:execute c "SELECT * FROM t")))

(stack-sql:with-transaction (c)
  (stack-sql:execute c "INSERT INTO t (name) VALUES (?)" '("grace")))

(let ((pool (stack-sql:make-pool stack-sql:*sql-backend*
                                 :database-name ":memory:"
                                 :max 4)))
  (stack-sql:with-pool-connection (c pool)
    (stack-sql:ping c)))
```

Postgres (optional):

```lisp
(asdf:load-system "sql-backend-postgres")
(stack-sql:connect :driver :postgres
                   :database-name "app"
                   :username "app"
                   :password "secret")
```

## Tests

```bash
# from this repo, with CL_SOURCE_REGISTRY including this tree + Quicklisp
ros -e '(asdf:test-system "sql-protocol")' -q

# optional live Postgres
SQL_POSTGRES=1 ros -e '(asdf:test-system "sql-protocol")' -q
```

## License

MIT — see [LICENSE](LICENSE).
