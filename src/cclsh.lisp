;;;; cclsh.lisp -- the cclsh surface of cclsh-elisp.
;;;;
;;;;   elisp                      interactive elisp> loop
;;;;   elisp -e '(+ 1 2)'         evaluate and print (quote it: cclsh evaluates a
;;;;                              bare (...) argument as Common Lisp first)
;;;;   elisp file.el ...          load files (defuns stay in the session)
;;;;   (elisp-eval "(car '(a b))") from Lisp: the last value, as Lisp data


(in-package #:cclsh-user)

(defun elisp-eval (source)
  "Evaluate Elisp SOURCE natively; return the last value as Lisp data."
  (elisp:eval-string source))

(defcommand elisp (&rest arguments)
  "Native Elisp: no args = elisp> loop; -e FORM = print FORM's value; FILE... = load files."
  (cond ((null arguments) (elisp:repl) 0)
        ((string= (first arguments) "-e")
         (elisp::report (lambda () (elisp:eval-string (format nil "~{~a~^ ~}" (rest arguments)))))
         0)
        (t (dolist (file arguments 0)
             (elisp::report (lambda () (elisp:load-file file)))))))
