;;; yatt-lint-any.el -- *Minor* mode to lint any (yatt related) files.

;;; Copyright (C) 2010 KOBAYASI Hiroaki

;; Author: KOBAYASI Hiroaki <hkoba@cpan.org>

;; TODO: lint *before* real file saving, for safer operation.

(require 'cl)

(require 'plist-bind "yatt/utils")

(defconst yatt-lint-any-YATT-dir
  ;; eval-current-buffer で nil に戻されないように
  (let ((fn load-file-name))
    (if fn
	(file-name-directory
	 (directory-file-name
	  (file-name-directory
	   (file-truename fn))))
      yatt-lint-any-YATT-dir))
  "Where YATT is installed. This is used to locate ``scripts/yatt.lint''.")

(defvar yatt-lint-any-registry
  ;; User may extend this.
  '(("\\.yatt\\'"
     after yatt-lint-any-handle-yatt)
    ("\\.ydo\\'"
     after yatt-lint-any-handle-perl-action)
    ("\\.htyattrc\\.pl\\'"
     after yatt-lint-any-handle-yattrc)
    ("\\.pm\\'"
     after yatt-lint-any-handle-perl-module)
    )
  "Auto lint filename mapping for yatt and related files.")

(defvar yatt-lint-any-mode-map (make-sparse-keymap))
(define-key yatt-lint-any-mode-map [f5] 'yatt-lint-any-after)

(define-minor-mode yatt-lint-any-mode
  "Lint anything, by hitting <F5>"
  :keymap yatt-lint-any-mode-map
  :lighter "<F5 lint>"
  :global nil
  (let ((hook 'after-save-hook) (fn 'yatt-lint-any-after))
    (if yatt-lint-any-mode
	(add-hook hook fn nil nil)
      (remove-hook hook fn nil))))

(defun yatt-lint-any-after ()
  "lint after file save."
  (interactive)
  (let* ((buf (current-buffer))
	 (spec (yatt-lint-any-lookup
		(file-name-nondirectory (buffer-file-name buf))))
	 (handler (and spec (plist-get spec 'after))))
    (when handler
      (yatt-lint-any-run handler buf))))

(defun yatt-lint-any-lookup (bufname &optional registry)
  (setq registry (or registry yatt-lint-any-registry))
  (save-match-data
    (block loop
      (while registry
	(when (string-match (caar registry) bufname)
	  (return-from loop (cdar registry)))
	(setq registry (cdr registry))))))

(defun yatt-lint-any-run (handler buffer)
  (plist-bind (file line err rc)
      (funcall handler buffer)
    (unless (eq rc 0)
      (beep))
    (when (and file line)
      (when (and (not (equal (expand-file-name file) (buffer-file-name buffer)))
	       (not (equal file "-")))
	(message "opening error file: %s" file)
	(find-file-other-window file))
      (goto-line (string-to-number line)))
    (message "%s"
	     (cond ((> (length err) 0)
		    err)
		   ((not (eq rc 0))
		    "Unknown error")
		   (t
		    "lint OK")))))

;;========================================
;; *.yatt
;;========================================
(defun yatt-lint-any-handle-yatt (buffer)
  (plist-bind (rc err)
      (yatt-lint-any-shell-command "scripts/yatt.lint" " "
				   (buffer-file-name buffer))
    (when rc
      (let (match diag)
	;; う～ん、setq がダサくないか? かといって、any-matchのインデントが深くなるのも嫌だし...
	(cond ((setq match
		     (yatt-lint-any-match
		      "^\\[\\[file\\] \\([^]]*\\) \\[line\\] \\([^]]*\\)\\]\n"
		      err 'file 1 'line 2))
	       (setq diag (substring err (plist-get match 'end)
				     (plist-get (yatt-lint-any-match
						 "\\s-+\\'" err) 'pos))))
	      ((setq match
		     (yatt-lint-any-match
		      " at \\([^ ]*\\) line \\([0-9]+\\)[.,]"
		      err 'file 1 'line 2))
	       (setq diag (substring err 0 (plist-get match 'pos)))))
	(append `(rc ,rc err ,(or diag err)) match)))))


(defun yatt-lint-any-handle-yattrc (buffer)
  (yatt-lint-any-shell-command "scripts/yatt.lintrc" " "
			       (buffer-file-name buffer)))

(defun yatt-lint-any-handle-perl-action (buffer)
  (yatt-lint-any-shell-command "scripts/yatt.lintany" " "
			       (buffer-file-name buffer)))

(defun yatt-lint-any-handle-perl-module (buffer)
  (plist-bind (rc err)
      (yatt-lint-any-shell-command "scripts/yatt.lintpm" " "
				   (buffer-file-name buffer))
    (when rc
      (let (match diag)
	(cond ((setq match
		     (yatt-lint-any-match
		      " at \\([^ ]*\\) line \\([0-9]+\\)[.,]"
		      err 'file 1 'line 2))
	       (setq diag (substring err 0 (plist-get match 'pos)))))
	(append `(rc ,rc err ,diag) match)))))

;;========================================
;; Other utils
;;========================================
(defun yatt-lint-any-shell-command (cmdfile &rest args)
  (let ((tmpbuf (generate-new-buffer " *yatt-lint-temp*"))
	(cmd (concat yatt-lint-any-YATT-dir "/" cmdfile))
	rc err)
    (unless (file-exists-p cmd)
      (error "Can't find yatt command: %s" cmdfile))
    (unwind-protect
	(setq rc (shell-command (apply #'concat cmd args) tmpbuf))
      (setq err (with-current-buffer tmpbuf (buffer-string)))
      (kill-buffer tmpbuf))
    `(rc ,rc err ,err)))

(defun yatt-lint-any-match (pattern str &rest key-offset)
  "match PATTERN to STR and extract match-portions specified by KEY-OFFSET."
  (let (res spec key off pos end)
    (save-match-data
      (when (setq pos (string-match pattern str))
	(setq end (match-end 0))
	(while key-offset
	  (setq key (car key-offset)
		off (cadr key-offset))
	  (setq res (append (list key (match-string off str)) res))
	  (setq key-offset (cddr key-offset)))
	(append `(pos ,pos end ,end) res)))))

'(let ((err
       "Global symbol \"$unknown_var\" requires explicit package name at samples/basic/1/perlerr.yatt line 2.\n"))
  (yatt-lint-any-match
   "^\\[\\[file\\] \\([^]]*\\) \\[line\\] \\([^]]*\\)\\]\n"
   err 'file 1 'line 2)
  (yatt-lint-any-match
   " at \\([^ ]*\\) line \\([0-9]+\\)\\.\n"
   err 'file 1 'line 2))

'(let ((err
       "syntax error at ./index.yatt line 37, at EOF"))
  (yatt-lint-any-match
   " at \\([^ ]*\\) line \\([0-9]+\\)[.,]"
   err 'file 1 'line 2))

(provide 'yatt-lint-any-mode)
