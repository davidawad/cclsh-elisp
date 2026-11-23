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
;;;; functions there are always available. (elisp-autoload-directory DIR)
;;;; registers every function defined under DIR without loading anything; a
;;;; file loads the first time one of its functions is called.

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

(defvar *elisp-path-index* nil "(PATH-string . hash of program names on it).")

(defvar *elisp-path-current* nil
  "True while a batch of names is checked against an index known to be fresh.")

(defun elisp--program-p (name)
  "True when NAME is a program on PATH. One directory listing per PATH
directory, rebuilt when PATH changes, instead of a probe per name."
  (let ((path (if (and *elisp-path-current* *elisp-path-index*)
                  (car *elisp-path-index*)
                  (or (getenv "PATH") ""))))
    (unless (equal (car *elisp-path-index*) path)
      (let ((names (make-hash-table :test #'equal)))
        (dolist (dir (uiop:split-string path :separator '(#\:)))
          (when (plusp (length dir))
            (dolist (f (ignore-errors (uiop:directory-files (uiop:ensure-directory-pathname dir))))
              (setf (gethash (file-namestring f) names) t))))
        (setf *elisp-path-index* (cons path names))))
    (gethash name (cdr *elisp-path-index*))))

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
      (unless (elisp--program-p name)
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

(defvar *elisp-autoloaded-files* (make-hash-table :test #'equal))

(defun elisp--autoload-file (file)
  (unless (gethash file *elisp-autoloaded-files*)
    (setf (gethash file *elisp-autoloaded-files*) t)
    (let ((*error-output* (make-broadcast-stream)))
      (elisp:load-file file))))

(defun elisp--walk (directory exclude)
  "(values DIRECTORIES FILES) under DIRECTORY: namestrings, skipping
subdirectories named in EXCLUDE; FILES are the *.el files."
  (let ((dirs '()) (files '()))
    (labels ((walk (dir)
               (push (namestring dir) dirs)
               (dolist (f (uiop:directory-files dir "*.el")) (push (namestring f) files))
               (dolist (sub (uiop:subdirectories dir))
                 (unless (member (car (last (pathname-directory sub))) exclude :test #'string=)
                   (walk sub)))))
      (walk (uiop:ensure-directory-pathname directory)))
    (values (nreverse dirs) (nreverse files))))

(defun elisp--scan-names (file)
  "Names of the functions FILE defines at top level."
  (let ((names '()))
    (cl-ppcre:do-register-groups (name)
        ("(?m)^\\((?:defun|defsubst|defalias +'|define-inline) +([^ ()\\n]+)"
         (or (ignore-errors (uiop:read-file-string file)) ""))
      (push name names))
    (nreverse names)))

(defun elisp--index-cache (directory exclude)
  (uiop:xdg-cache-home "cclsh" "elisp-autoload"
                       (format nil "~36r.tsv" (sxhash (format nil "~a~s" directory exclude)))))

(defun elisp--read-index (cache-file)
  "(values DIRS FILES) from CACHE-FILE: lines \"d<TAB>mtime<TAB>path\" and
\"f<TAB>mtime<TAB>path<TAB>name...\"; NIL when absent or unreadable."
  (handler-case
   (with-open-file (in cache-file)
     (let ((dirs '()) (files '()))
       (loop for line = (read-line in nil) while line
             do (let ((parts (uiop:split-string line :separator '(#\Tab))))
                  (if (string= (first parts) "d")
                      (push (cons (third parts) (parse-integer (second parts))) dirs)
                      (push (list (third parts) (parse-integer (second parts)) (cdddr parts)) files))))
       (values (nreverse dirs) (nreverse files))))
    (error () (values nil nil))))

(defun elisp--write-index (cache-file dirs files)
  (ignore-errors
   (ensure-directories-exist cache-file)
   (with-open-file (out cache-file :direction :output :if-exists :supersede)
     (dolist (d dirs) (format out "d~c~d~c~a~%" #\Tab (cdr d) #\Tab (car d)))
     (dolist (f files)
       (format out "f~c~d~c~a~{~c~a~}~%" #\Tab (second f) #\Tab (first f)
               (mapcan (lambda (n) (list #\Tab n)) (third f)))))))

(defun elisp--index (directory exclude)
  "((file . names) ...) for DIRECTORY, from a cache that is checked with one
stat per directory and file; only changed files are read again."
  (let ((cache-file (elisp--index-cache directory exclude)))
    (multiple-value-bind (dirs files) (elisp--read-index cache-file)
      (flet ((mtime (f)
               ;; One stat(2); file-write-date resolves the truename first.
               #+sbcl (or (ignore-errors (sb-posix:stat-mtime (sb-posix:stat f))) 0)
               #-sbcl (or (ignore-errors (file-write-date f)) 0)))
        (if (and dirs (every (lambda (d) (eql (mtime (car d)) (cdr d))) dirs)
                 (every (lambda (f) (eql (mtime (first f)) (second f))) files))
            (mapcar (lambda (f) (cons (first f) (third f))) files)
            (multiple-value-bind (dir-list file-list) (elisp--walk directory exclude)
              (let* ((old (make-hash-table :test #'equal))
                     (entries
                       (progn (dolist (f files) (setf (gethash (first f) old) f))
                              (mapcar (lambda (path)
                                        (let ((m (mtime path)) (prev (gethash path old)))
                                          (list path m (if (and prev (eql (second prev) m))
                                                           (third prev)
                                                           (elisp--scan-names path)))))
                                      file-list))))
                (elisp--write-index cache-file
                                    (mapcar (lambda (d) (cons d (mtime d))) dir-list)
                                    entries)
                (mapcar (lambda (f) (cons (first f) (third f))) entries))))))))

(defun elisp-autoload-directory (directory &key (exclude '(".git" "test" "tests" "vendor" "elpa"
                                                           ".local" "straight" "eln-cache")))
  "Make every function defined in the *.el files under DIRECTORY callable
now, loading its file on the first call (like Emacs autoloads): startup
only reads a cached name index. Returns the number of functions registered."
  (when (and (stringp directory) (uiop:string-prefix-p "~/" directory))
    (setf directory (concatenate 'string (getenv "HOME") (subseq directory 1))))
  (elisp--program-p "")                 ; refresh the PATH index once
  (let ((count 0) (*elisp-path-current* t))
    (dolist (entry (elisp--index directory exclude) count)
      (let ((path (car entry)))
        (dolist (name (cdr entry))
          (let ((esymbol (elisp::esym name)))
            (unless (gethash esymbol elisp::*functions*)
              (incf count)
              (let (stub)
                (setf stub (lambda (&rest arguments)
                             (elisp--autoload-file path)
                             (let ((real (gethash esymbol elisp::*functions*)))
                               (when (or (null real) (eq real stub))
                                 (elisp::signal-elisp "void-function" esymbol))
                               (apply real arguments))))
                (elisp::define-function esymbol stub)))))))))

(elisp-load-directory)
