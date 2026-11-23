;;;; cclsh-elisp: run Emacs Lisp natively inside cclsh (no Emacs).

(defsystem "cclsh-elisp/core"
  :description "An Emacs Lisp interpreter in Common Lisp for editor-independent Elisp."
  :license "ISC"
  :depends-on ("cl-ppcre" "uiop")
  :pathname "src/"
  :components ((:file "elisp")))

(defsystem "cclsh-elisp"
  :description "cclsh plugin: the `elisp' command and `elisp-eval', backed by cclsh-elisp/core."
  :license "ISC"
  :depends-on ("cclsh-elisp/core" "cclsh" (:feature :sbcl "sb-posix"))
  :pathname "src/"
  :components ((:file "cclsh")))

(defsystem "cclsh-elisp/tests"
  :depends-on ("cclsh-elisp/core")
  :pathname "tests/"
  :components ((:file "tests"))
  :perform (test-op (o c) (uiop:symbol-call '#:cclsh-elisp-tests '#:run)))
