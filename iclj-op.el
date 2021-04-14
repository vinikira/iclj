;;; iclj-op.el --- summary -*- lexical-binding: t -*-
;;
;; Author: lambdart <lambdart@protonmail.com>
;; Maintainer: lambdart
;; Homepage: https://github.com/lambdart/iclj
;; Version: 0.0.1 Alpha
;; Keywords:
;;
;; This file is NOT part of GNU Emacs.
;;
;;; MIT License
;;
;; Copyright (c) 2020 lambdart
;;
;; Permission is hereby granted, free of charge, to any person obtaining a copy
;; of this software and associated documentation files (the "Software"), to deal
;; in the Software without restriction, including without limitation the rights
;; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;; copies of the Software, and to permit persons to whom the Software is
;; furnished to do so, subject to the following conditions:
;;
;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.
;;
;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;; SOFTWARE.
;;
;;; Commentary:
;;
;;; Code:

(require 'clojure-mode)

(require 'iclj-comint)
(require 'iclj-completion)

(defvar iclj-op-eldoc-format
  "(let [m (clojure.core/meta #'%s)]
     (flatten
        (list (str (get m :name))
              (str (first (get m :arglists)))
              (get m :doc))))"
  "Eldoc operation format.")

(defvar iclj-op-alist
  `((input          . (nil "%s"))
    (eval           . (nil "%s"))
    (eval-last-sexp . (iclj-overlay-handler "%s"))
    (load-file      . (nil "(clojure.core/load-file %S)"))
    (doc            . (nil "(clojure.repl/doc %s)"))
    (find-doc       . (nil "(clojure.repl/find-doc %S)"))
    (eldoc          . (nil ,iclj-op-eldoc-format))
    (source         . (nil "(clojure.repl/source %s)"))
    (complete       . (iclj-completion-handler "(clojure.repl/apropos %S)"))
    (apropos        . (iclj-apropos-handler "(sort (clojure.repl/apropos %S))"))
    (meta           . (nil "(clojure.pprint/pprint (clojure.core/meta #'%s))"))
    (macroexpand    . (nil "(clojure.pprint/pprint (clojure.core/macroexpand '%s))"))
    (macroexpand-1  . (nil "(clojure.pprint/pprint (clojure.core/macroexpand-1 '%s))"))
    (ns-vars        . (nil "(clojure.repl/dir %s)"))
    (set-ns         . (nil "(clojure.core/in-ns '%s)")))
  "Operation associative list: (OP-KEY . (OP-FN OP-FMT).
OP-KEY, the operation key selector.
OP-RESP-HANDLER, the operation display response function,
manly used to parse/display the resulting text output.
OP-FMT-STRING, the operation format string.")

(defun iclj-op-dispatch (op-key input-type &optional echo no-display &rest input)
  "Dispatch the operation defined by OP-KEY.
INPUT-TYPE, the string \"region\" or \"string\".
If ECHO is non-nil, mirror the output in the comint buffer.
If NO-DISPLAY is non-nil, don't display the auxiliary output buffer.
INPUT, the string or the region bounds."
  (let ((op (cdr (assoc op-key iclj-op-alist)))) ; select operation-format
    ;; verify if operation exists in the table
    (if (not op) (message "Error, operation not found")
      ;; get its response handler function
      (let ((op-resp-handler (car op))
            ;; get its format
            (op-fmt-string (cadr op)))
        ;; set comint display function callback and cache the current buffer
        (setq iclj-comint-resp-handler op-resp-handler
              iclj-comint-from-buffer (current-buffer))
        ;; send the parsed input to REPL process/buffer
        (apply 'iclj-comint-redirect-input-to-process
               ;; set process send function
               (intern (concat "process-send-" input-type))
               ;; from current buffer
               (current-buffer)
               ;; mirror output to comint buffer?
               echo
               ;; display output?
               no-display
               ;; format string or send region (beg/end)?
               (if (> (length input) 1) input
                 (list (format op-fmt-string (car input)))))))))

(defun iclj-op-thing-at-point (&optional thing)
  "Return THING at point.
See the documentation of `thing-at-point' to understand what
thing means."
  (let* ((thing (or thing 'symbol))
         (bounds (bounds-of-thing-at-point thing)))
    (if (not bounds) ""
      (buffer-substring-no-properties (car bounds)
                                      (cdr bounds)))))

(defun iclj-op-minibuffer-read (&optional thing prompt)
  "Read string using minibuffer.
THING, non-nil means grab thing at point (default).
PROMPT, non-nil means minibuffer prompt."
  (let* ((def (iclj-op-thing-at-point thing))
         (fmt (if (not thing) "%s: " "%s[%s]: "))
         (prompt (format fmt (or prompt "String") def)))
    ;; return the read list string
    (list (read-string prompt nil nil def))))

(defun iclj-op-eval-defn ()
  "Send definition to the Clojure comint process."
  (interactive)
  (save-excursion
    (end-of-defun)
    (let ((end (point)))
      (beginning-of-defun)
      (iclj-op-dispatch 'eval-last "region" nil t (point) end))))

(defun iclj-op-eval-sexp (sexp)
  "Eval SEXP string, i.e, send it to Clojure comint process."
  (interactive (iclj-op-minibuffer-read 'sexp "Eval"))
  ;; eval string symbolic expression
  (iclj-op-dispatch 'eval "string" nil nil sexp))

(defun iclj-op-eval-last-sexp ()
  "Send the previous sexp to the inferior process."
  (interactive)
  ;; send region of the last expression
  (iclj-op-dispatch 'eval-last-sexp "region" nil t
                    (save-excursion (backward-sexp) (point)) (point)))

(defun iclj-op-eval-region (beg end)
  "Eval BEG/END region."
  (interactive "r")
  (iclj-op-dispatch 'eval "region" nil nil beg end))

(defun iclj-op-eval-buffer ()
  "Eval current buffer."
  (interactive)
  (save-excursion
    (widen)
    (let ((case-fold-search t))
      (iclj-op-dispatch 'eval "region" nil nil (point-min) (point-max)))))

(defun iclj-op-eval-file (filename)
  "Read FILENAME and evaluate it's region contents."
  (interactive "fFile: ")
  ;; insert buffer contents and call eval buffer operation
  (with-temp-buffer
    (insert-file-contents-literally filename)
    (iclj-op-eval-buffer)))

(defvar iclj-op-prev-l/c-dir/file nil
  "Caches the last (directory . file) pair.")

(defvar iclj-source-modes '(clojure-mode)
  "Used to determine if a buffer contains clojure source code.
If it's loaded into a buffer that is in one of these major modes, it's
considered a Clojure source file by `iclj-load-file'.")

(defun iclj-op-load-file (filename)
  "Load the target FILENAME."
  (interactive (comint-get-source "File: "
                                  iclj-op-prev-l/c-dir/file
                                  iclj-source-modes t))
  ;; if the file is loaded into a buffer, and the buffer is modified, the user
  ;; is queried to see if he wants to save the buffer before proceeding with
  ;; the load or compile
  (comint-check-source filename)
  ;; cache previous directory/filename
  (setq iclj-op-prev-l/c-dir/file
        (cons (file-name-directory filename)
              (file-name-nondirectory filename)))
  ;; load file operation
  (iclj-op-dispatch 'load "string" nil nil filename))

(defun iclj-op-load-buffer-file-name ()
  "Load current buffer."
  (interactive)
  (let ((filename (buffer-file-name)))
    ;; load file operation
    (iclj-op-load-file filename)))

(defun iclj-op-doc (input)
  "Describe identifier INPUT (string) operation."
  (interactive (iclj-op-minibuffer-read 'sexp "Doc"))
  ;; documentation operation
  (iclj-op-dispatch 'doc "string" nil nil input))

(defun iclj-op-find-doc (input)
  "Find INPUT documentation ."
  (interactive (iclj-op-minibuffer-read nil "Find-doc"))
  ;; doc-dwin operation
  (iclj-op-dispatch 'find-doc "string" nil nil input))

(defun iclj-op-apropos (input)
  "Invoke Clojure (apropos INPUT) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Apropos"))
  ;; send apropos operation
  (iclj-op-dispatch 'apropos "string" nil t input))

(defun iclj-op-ns-vars (nsname)
  "Invoke Clojure (dir NSNAME) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Ns vars"))
  ;; send ns-vars operation
  (iclj-op-dispatch 'ns-vars "string" nil nil nsname))

(defun iclj-op-set-ns (name)
  "Invoke Clojure (in-ns NAME) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Set Ns"))
  ;; send set-ns operation
  (iclj-op-dispatch 'set-ns "string" nil nil name))

(defun iclj-op-source (name)
  "Invoke Clojure (source NAME) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Symbol"))
  ;; send source operation
  (iclj-op-dispatch 'source "string" nil nil name))

(defun iclj-op-meta (symbol)
  "Invoke Clojure (meta #'SYMBOL) operation."
  ;; map string function parameter
  (interactive (iclj-op-minibuffer-read nil "Symbol"))
  ;; send meta operation
  (iclj-op-dispatch 'meta "string" nil nil symbol))

(defun iclj-op-eldoc (symbol)
  "Invoke \\{iclj-op-eldoc-format} operation.
SYMBOL, clojure symbol that'll be extract the necessary metadata."
  (iclj-op-dispatch 'eldoc "string" nil nil symbol))

(defun iclj-op-complete ()
  "Invoke Clojure complete operation."
  ;; map string function parameter
  (interactive)
  ;; set completion bounds (beg/end)
  (iclj-completion-set-bounds)
  ;; dispatch the complete operation
  (let ((initial-input (iclj-completion-initial-input)))
    (when initial-input
      (iclj-op-dispatch 'complete "string" nil t initial-input))))

(defun iclj-op-macroexpand ()
  "Invoke Clojure (macroexpand form) operation."
  (interactive)
  (let ((form (buffer-substring-no-properties
               (save-excursion (backward-sexp) (point)) (point))))
    (iclj-op-dispatch 'macroexpand "string" nil nil form)))

(defun iclj-op-macroexpand-1 ()
  "Invoke Clojure (macroexpand-1 form) operation."
  (interactive)
  (let ((form (buffer-substring-no-properties
               (save-excursion (backward-sexp) (point)) (point))))
    (iclj-op-dispatch 'macroexpand-1 "string" nil nil form)))

(provide 'iclj-op)

;;; iclj-op.el ends here
