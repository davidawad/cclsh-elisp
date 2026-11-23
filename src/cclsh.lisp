;;;; cclsh.lisp -- the cclsh surface of cclsh-elisp.
;;;;
;;;; Every Elisp function becomes a cclsh function and command of the same
;;;; name, as soon as it is defined (in the elisp> loop, by -e, or by a
;;;; loaded file):
;;;;
;;;;   greet david                shell style: arguments are strings (numbers
;;;;                              when they read as numbers); prints the result
;;;;   (greet "david")            Lisp style: returns the value; Lisp symbols
;;;;   (beads 'awad-law)          become Elisp symbols, and back
;;;;
;;;; A name that is already a cclsh command, a Common Lisp symbol or a
;;;; function defined elsewhere keeps its meaning; call the Elisp one with
;;;; (elisp-call 'name ...) instead. A name that is also a program on PATH
;;;; gets only the Lisp function: `ls' at the prompt stays /bin/ls.
;;;;
;;;;   elisp                      interactive elisp> loop
;;;;   elisp -e "(+ 1 2)"         evaluate and print (quote it: cclsh evaluates a
;;;;                              bare (...) argument as Common Lisp first)
;;;;   elisp file.el ...          load files
;;;;   (elisp-eval "(car '(a b))") from Lisp: the last value, as Lisp data
;;;;
;;;; At startup every *.el file in ~/.config/cclsh/elisp/ is loaded, so the
;;;; functions there are always available.

(in-package #:cclsh-user)

;;; -- Values across the boundary --

(defun elisp--to (x)
  "A Common Lisp value as Elisp: symbols downcased into Elisp, chars as codes."
  (cond ((or (null x) (eq x t) (keywordp x)) x)
        ((symbolp x) (elisp::esym (string-downcase (symbol-name x))))
        ((characterp x) (char-code x))
        ((consp x) (cons (elisp--to (car x)) (elisp--to (cdr x))))
        ((and (vectorp x) (not (stringp x))) (map 'vector #'elisp--to x))
        (t x)))

(defun elisp--from (x)
  "An Elisp value as Common Lisp: Elisp symbols become cclsh-user symbols."
  (cond ((and (symbolp x) x (eq (symbol-package x) (find-package '#:elisp-sym)))
         (intern (string-upcase (symbol-name x)) '#:cclsh-user))
        ((consp x) (cons (elisp--from (car x)) (elisp--from (cdr x))))
        ((and (vectorp x) (not (stringp x))) (map 'vector #'elisp--from x))
        (t x)))

(defun elisp--shell-argument (word)
  "A command-line WORD as an Elisp argument: a number when it reads as one."
  (let ((n (and (plusp (length word))
                (every (lambda (c) (or (digit-char-p c) (find c "+-.eE"))) word)
                (ignore-errors (let ((*read-eval* nil)
                                     (*read-default-float-format* 'double-float))
                                 (read-from-string word))))))
    (if (numberp n) n word)))

;;; -- Exposing Elisp functions --

(defvar *elisp-exposed* (make-hash-table :test #'eq)
  "cclsh-user symbols this plugin defined from Elisp functions.")

(defun elisp-call (name &rest arguments)
  "Call Elisp function NAME (a symbol or string) with Lisp ARGUMENTS."
  (let ((symbol (elisp::esym (if (stringp name) name (string-downcase (symbol-name name))))))
    (elisp--from (apply (elisp::callable symbol) (mapcar #'elisp--to arguments)))))

(defun elisp--expose (esymbol function)
  "Define a cclsh function and command named like Elisp's ESYMBOL."
  (let* ((name (symbol-name esymbol))
         (symbol (and (string= name (string-downcase name))
                      (intern (string-upcase name) '#:cclsh-user))))
    (when (and symbol
               (eq (symbol-package symbol) (find-package '#:cclsh-user))
               (or (gethash symbol *elisp-exposed*)
                   (not (or (fboundp symbol) (boundp symbol) (constantp symbol)))))
      (setf (gethash symbol *elisp-exposed*) t)
      (setf (symbol-function symbol)
            (lambda (&rest arguments)
              (elisp--from (apply function (mapcar #'elisp--to arguments)))))
      ;; The command name: never take it from a program on PATH (an Elisp
      ;; `ls' must not replace /bin/ls at the prompt); (ls) still reaches it.
      (unless (cclsh::path-search name)
       (proclaim `(special ,symbol))
       (setf (symbol-value symbol)
            (make-instance 'cclsh::command
                           :name symbol
                           :documentation (format nil "Elisp function ~a" name)
                           :function (symbol-function symbol)
                           :arguments '()
                           :declarative-arguments-p t
                           :invoker
                           (lambda (words)
                             (handler-case
                                 (let ((value (apply function (mapcar #'elisp--shell-argument words))))
                                   (when value (write-line (elisp:princ-string value)))
                                   0)
                               (error (c)
                                 (format *error-output* "~a: ~a~%" name
                                         (if (typep c 'elisp::elisp-error)
                                             (elisp:prin1-string (cons (elisp::error-symbol c)
                                                                       (elisp::error-data c)))
                                             (elisp::one-line c)))
                                 1))))))
      symbol)))

(pushnew 'elisp--expose elisp:*define-function-hook*)

;;; -- Commands --

(defun elisp-eval (source)
  "Evaluate Elisp SOURCE natively; return the last value as Lisp data."
  (elisp--from (elisp:eval-string source)))

(defcommand elisp (&rest arguments)
  "Native Elisp: no args = elisp> loop; -e FORM = print FORM's value; FILE... = load files."
  (cond ((null arguments) (elisp:repl) 0)
        ((string= (first arguments) "-e")
         (elisp:report (lambda () (elisp:eval-string (format nil "~{~a~^ ~}" (rest arguments)))))
         0)
        (t (dolist (file arguments 0)
             (elisp:report (lambda () (elisp:load-file file)))))))

(defun elisp-load-directory (&optional (directory (merge-pathnames "cclsh/elisp/" (uiop:xdg-config-home))))
  "Load every *.el file in DIRECTORY (default ~/.config/cclsh/elisp/)."
  (dolist (file (sort (directory (merge-pathnames "*.el" directory))
                      #'string< :key #'namestring))
    (elisp:load-file file)))

(elisp-load-directory)
