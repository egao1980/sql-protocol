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

;; Prefer GHCR once imports land; :ql is a temporary force until publish greens.
;; cl-postgres ships inside the Quicklisp *postmodern* release — force-load it
;; explicitly so dbd-postgres can resolve the ASDF component.
(call-with-ci-muffles
 (lambda ()
   (ql:quickload '("postmodern" "cl-postgres" "dbd-postgres" "dbd-sqlite3") :silent t)
   (cl-repo:ensure-system-dependencies "sql-protocol"
     :also-tests t
     :with '("sql-backend-sqlite3" "sql-backend-postgres")
     :sources '(("dbd-sqlite3" :ql)
                ("dbd-postgres" :ql)
                ("dbi" :ql)
                ("cl-dbi" :ql)
                ("sqlite" :ql)
                ("cl-postgres" :ql)
                ("uax-15" :ql)
                ("bordeaux-threads" :ql)
                ("split-sequence" :ql)
                ("closer-mop" :ql)
                ("cl-ppcre" :ql)
                ("trivial-garbage" :ql)
                ("md5" :ql)
                ("ironclad" :ql)
                ("cl-base64" :ql)
                ("rove" :ql)))))

(format t "~&; ci: postgres install phase done~%")
(uiop:quit 0)
