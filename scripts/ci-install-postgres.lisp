;;;; Phase 1 (postgres job): install SUT + sqlite3 + postgres backends via cl-repo.

(setf *debugger-hook*
      (lambda (c h)
        (declare (ignore h))
        (format *error-output* "~&UNHANDLED: ~A~%" c)
        (uiop:quit 1)))

(setf asdf:*compile-file-failure-behaviour* :warn)

(defun call-with-ci-muffles (fn)
  #+sbcl
  (handler-bind ((sb-ext:defconstant-uneql
                  (lambda (c)
                    (let ((r (find-restart 'continue c)))
                      (when r (invoke-restart r))))))
    (funcall fn))
  #-sbcl
  (funcall fn))

(call-with-ci-muffles (lambda () (asdf:load-system "cl-repository-client")))

(cl-repo:add-registry "https://ghcr.io" :namespace "egao1980/cl-systems" :priority :prepend)

;; Postgres driver stack via QL for now — GHCR cl-postgres + ironclad/cl-base64
;; can trip cl-base64 decode-table load-order errors during SCRAM. sqlite path
;; stays on OCI (matrix job).
(call-with-ci-muffles
 (lambda ()
   (ql:quickload '("cl-base64" "md5" "ironclad" "uax-15" "cl-postgres"
                   "dbd-postgres" "dbd-sqlite3")
                 :silent t)
   (cl-repo:ensure-system-dependencies "sql-protocol"
     :also-tests t
     :with '("sql-backend-sqlite3" "sql-backend-postgres")
     :sources '(("cl-postgres" :ql)
                ("dbd-postgres" :ql)
                ("cl-base64" :ql)
                ("ironclad" :ql)
                ("md5" :ql)
                ("uax-15" :ql)
                ("dbd-sqlite3" :oci)
                ("dbi" :oci)
                ("sqlite" :oci)))))

(format t "~&; ci: postgres install phase done~%")
(uiop:quit 0)
