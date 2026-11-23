;;; programs.el --- whole Elisp programs the tests load  -*- lexical-binding: t -*-

;; An RFC 4180 CSV parser: cl-flet, characters as integers, push/nreverse.
(defun csv-parse (text)
  (let ((rows nil) (row nil) (field nil) (in-quote nil) (i 0) (n (length text)))
    (cl-flet ((end-field () (push (apply #'string (nreverse field)) row)
                (setq field nil))
              (end-row () (when row (push (nreverse row) rows)) (setq row nil)))
      (while (< i n)
        (let ((c (aref text i)))
          (cond
           ((and in-quote (eq c ?\") (< (1+ i) n) (eq (aref text (1+ i)) ?\"))
            (push ?\" field) (cl-incf i))
           ((and in-quote (eq c ?\")) (setq in-quote nil))
           (in-quote (push c field))
           ((eq c ?\") (setq in-quote t))
           ((eq c ?,) (end-field))
           ((eq c ?\r))
           ((eq c ?\n) (when (or field row) (end-field) (end-row)))
           (t (push c field))))
        (cl-incf i))
      (when (or field row) (end-field) (end-row)))
    (nreverse rows)))

(defun csv-test ()
  (csv-parse "a,b\n\"q,1\",\"say \"\"hi\"\"\"\r\n\n"))

;; cl-loop building alists from a header row.
(defun rows-test ()
  (let ((header '("key" "action")))
    (mapcar (lambda (cells)
              (cl-loop for h in header for i from 0 collect (cons h (nth i cells))))
            '(("C-x" "save") ("M-q" "fill")))))

;; A chord parser: anchored Emacs regexps, match-string, user-error.
(defconst chord-modifiers '(("ctrl" . ctrl) ("shift" . shift) ("alt" . alt)))
(defun chord-parse (chord)
  (let ((rest (string-trim chord)) (mods nil))
    (while (and (string-match "\\`\\([^+]+\\)\\+\\(.+\\)\\'" rest)
                (or (assoc (downcase (match-string 1 rest)) chord-modifiers)
                    (user-error "Unknown modifier %S" (match-string 1 rest))))
      (push (cdr (assoc (downcase (match-string 1 rest)) chord-modifiers)) mods)
      (setq rest (match-string 2 rest)))
    (cons (nreverse mods) rest)))
