# cclsh-elisp

A tool for running Emacs Lisp code from [cclsh](https://github.com/lambda-symbolics/cclsh),
the Common Lisp system shell. No Emacs process is involved: an Elisp
interpreter written in Common Lisp evaluates the code in the shell's own image.
Every Elisp function you define becomes a cclsh command and a Common Lisp
function of the same name, so your Elisp runs at the shell prompt like any
other command.

```
$ cat ~/.config/cclsh/elisp/notes.el
(defun slug (title) (downcase (replace-regexp-in-string "[^a-zA-Z0-9]+" "-" title)))
$ slug "Hello, World"          # shell style: arguments are strings (or numbers)
hello-world
$ (slug "Lisp Bridge")         # Lisp style: returns the value
"lisp-bridge"
$ (mapcar #'slug '("A b" "C d"))
("a-b" "c-d")
```

`.el` files in `~/.config/cclsh/elisp/` load at startup. To bring in a whole
Emacs config without paying for loading it, add this to `startup.lisp`:

```lisp
(elisp-autoload-directory "~/.config/emacs/lisp/")
```

Every function defined under that directory is callable immediately; its
file loads the first time one of its functions is called (like Emacs
autoloads). The name index is cached and checked with one `stat` per file, so
an unchanged tree registers thousands of functions in well under a second.
Functions that need buffers, windows or other editor state still signal
`(void-function NAME)` when called. Functions defined in
the `elisp>` loop, by `elisp -e` or by `elisp FILE.el` become commands the
moment they are defined. A name that is already a cclsh command, a Common Lisp
symbol or a program on `PATH` keeps that meaning at the prompt (`ls` stays
`/bin/ls`); the Elisp function is still reachable as `(name ...)` when the Lisp
name is free, or always as `(elisp-call 'name ...)`.

```
$ elisp
elisp> (defun greet (name) (format "hi %s, %d chars" name (length name)))
greet
elisp> (greet "david")
"hi david, 5 chars"
elisp> (cl-loop for i from 1 to 5 collect (* i i))
(1 4 9 16 25)
elisp> (insert "x")
(void-function insert)

$ elisp -e "(mapconcat #'upcase (split-string \"a b c\") \"-\")"
"A-B-C"
$ elisp ~/.config/emacs/lisp/my-utils.el     # load a file; its defuns stay defined
$ (+ 1 (elisp-eval "(* 6 7)"))               # from Common Lisp
43
```

Quote `-e` forms (double quotes, so Elisp's `'` and `#'` survive): cclsh
evaluates a bare `(...)` argument as Common Lisp first.

## What runs

The editor-independent part of Elisp: lexical closures, `defvar` specials with
dynamic `let`, `defmacro` and backquote, `condition-case`, `catch`/`throw`,
`unwind-protect`, `cl-loop` (common clauses), `cl-flet`, `cl-labels`,
`when-let`/`if-let`, `push`/`pop`/`setf`/`cl-incf` on simple places, strings and
characters-as-integers, `format`, Emacs-syntax regexps (`string-match`,
`match-string`, `replace-regexp-in-string`, translated to cl-ppcre), hash tables,
vectors, alists and plists, and the common `seq-`, `string-` and `cl-` helpers.

## What does not

Buffers, points, markers, windows, frames, overlays, text properties and
keymaps are Emacs's C core. Calling one signals `(void-function NAME)`. Loading
a file skips top-level forms that need them, reports each on one line, and
keeps the rest, so a file's pure functions still load. Not yet implemented:
`pcase`, `cl-defun`, `let-alist`, generalized `setf` beyond `car`/`cdr`/`nth`/
`gethash`/`aref`.

## Install

Clone beside your cclsh setup and load it from `~/.config/cclsh/startup.lisp`:

```lisp
(push #p"/path/to/cclsh-elisp/" asdf:*central-registry*)
(asdf:load-system "cclsh-elisp")
```

The interpreter alone (`cclsh-elisp/core`, depends only on cl-ppcre) also loads
in any Common Lisp without cclsh.

## Tests

```
./run-tests.sh          # plain SBCL + Quicklisp; no cclsh needed
```
