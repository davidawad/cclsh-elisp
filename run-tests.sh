#!/bin/sh
# Run the core tests in plain SBCL (no cclsh needed). Needs Quicklisp.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
exec "${SBCL:-sbcl}" --noinform --non-interactive --no-userinit \
  --load "${QUICKLISP_SETUP:-$HOME/quicklisp/setup.lisp}" \
  --eval "(push #p\"$here/\" asdf:*central-registry*)" \
  --eval '(ql:quickload "cl-ppcre" :silent t)' \
  --eval '(asdf:load-system "cclsh-elisp/tests")' \
  --eval '(uiop:quit (if (uiop:symbol-call (quote #:cclsh-elisp-tests) (quote #:run)) 0 1))'
