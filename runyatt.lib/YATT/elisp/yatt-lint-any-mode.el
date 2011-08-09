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
  '(("\\.\\(yatt\\|ytmpl\\)\\'"
     after yatt-lint-any-handle-yatt)
    ("\\.ydo\\'"
     after yatt-lint-any-handle-perl-action)
    ("\\.htyattrc\\.pl\\'"
     after yatt-lint-any-handle-yattrc)
    ("\\.pm\\'"
     after yatt-lint-any-handle-perl-module)
    ("\\.\\(pl\\|t\\)\\'"
     after yatt-lint-any-handle-perl-script)
    )
  "Auto lint filename mapping for yatt and related files.")

(defvar yatt-lint-any-mode-blacklist nil
  "Avoid yatt-lint if after-save-hook contains these syms.")

(defun yatt-lint-any-mode-unless-blacklisted ()
  (let ((ok t) (lst yatt-lint-any-mode-blacklist)
	i)
    (while (and ok lst)
      (setq i (car lst))
      (setq ok (and ok (not (cond ((symbolp i)
				   (memq i after-save-hook))
				  ((listp i)
				   (funcall i))
				  (t nil)))))
      (setq lst (cdr lst)))
    (cond (ok
	   (yatt-lint-any-mode t))
	  (yatt-lint-any-mode
	   (yatt-lint-any-mode nil)))))

(defvar yatt-lint-any-mode-map (make-sparse-keymap))
(define-key yatt-lint-any-mode-map [f5] 'yatt-lint-any-after)

(define-minor-mode yatt-lint-any-mode
  "Lint anything, by hitting <F5>"
  :keymap yatt-lint-any-mode-map
  :lighter "<F5 lint>"
  :global nil
  (let ((hook 'after-save-hook) (fn 'yatt-lint-any-after)
	(buf (current-buffer)))
    (cond ((and (boundp 'mmm-temp-buffer-name)
		(equal (buffer-name) mmm-temp-buffer-name))
	   (message "skipping yatt-lint-any-mode for %s" buf)
	   nil)
	  (yatt-lint-any-mode
	   (message "enabling yatt-lint-any-mode for %s" buf)
	   (add-hook hook fn nil nil)
	   (make-variable-buffer-local 'yatt-lint-any-driver-path))
	  (t
	   (message "disabling yatt-lint-any-mode for %s" buf)
	   (remove-hook hook fn nil)))))

(defvar yatt-lint-any-driver-path nil
  "runyatt.lib path for this buffer.")

(defun yatt-lint-any-find-driver (&optional reload)
  "Find and cache runyatt.lib path."
  (or
   (and (not reload) yatt-lint-any-driver-path)
   (setq yatt-lint-any-driver-path
	 (let ((htaccess ".htaccess")
	       (htyattcf ".htyattconfig.xhf") config
	       action driver libdir)
	   (cond ((and
		   ;; For vhost and non-standard DocumentRoot case,
		   ;; Please specify info{libdir: ...} in your .htyattconfig.xhf
		   (file-exists-p htyattcf)
		   (setq libdir (yatt-xhf-fetch htyattcf "info" "libdir")))
		  (concat libdir "/YATT"))

		 ((and (file-exists-p htaccess)
		       (setq action (yatt-lint-any-htaccess-find htaccess
				     "Action" "x-yatt-handler"))
		       (file-exists-p
			(setq libdir (yatt-lint-any-action-libdir action))))
		  (concat libdir "/YATT")
		  )
		 ((file-exists-p "cgi-bin/runyatt.cgi")
		  "cgi-bin/runyatt.lib/YATT")
		 )))))

(defun yatt-xhf-fetch (fn k1 k2)
  ;; No, this is adhoc. Real logic will be implemented later.
  (save-current-buffer
    (find-file-read-only fn)
    (goto-char 0)
    (let (res
	  (found (re-search-forward (concat "^" k1 "{\n" k2 ": ") nil t)))
      (when found
	(end-of-line)
	(setq res (buffer-substring found (point))))
      (kill-buffer (current-buffer))
      res
    )
  ))

(defun yatt-lint-any-htaccess-find (file config &rest keys)
  (save-excursion
    (save-match-data
      (save-window-excursion
	(let ((pat (concat "^" (combine-and-quote-strings (cons config keys)
							  "\\s-+")
			   "\\s-+"))
	      found)
	  (find-file file)
	  (unwind-protect
	      (progn
		(goto-char 0)
		(block loop
		  (while (setq found (re-search-forward pat nil t))
		    (end-of-line)
		    (return-from loop (buffer-substring found (point))))))
	    (kill-buffer (current-buffer))))))))

'(yatt-lint-any-action-libdir
 (yatt-lint-any-htaccess-find
  ".htaccess" "Action" "x-yatt-handler")
 t)

(defun yatt-lint-any-action-libdir (action &optional systype)
  "Resolve action location(url) to real path.
Currently only RHEL is supported."
  (save-match-data
    (let* ((user)
	   (driver-path
	    (cond ((string-match "^/~\\([^/]+\\)" action)
		   (concat "/home/"
			   (match-string 1 action)
			   "/public_html"
			   (substring action (match-end 0))))
		  (t
		   (concat "/var/www/html" action)))))
      (concat (file-name-sans-extension driver-path) ".lib"))))

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
    (when (and file
	       (not (equal (expand-file-name file) (buffer-file-name buffer)))
	       (not (equal file "-")))
	(message "opening error file: %s" file)
	(find-file-other-window file))
    (when (and file line)
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
      (yatt-lint-any-shell-command (yatt-lint-cmdfile "scripts/yatt.lint") " "
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
  (yatt-lint-any-perl-error-by
   (yatt-lint-cmdfile "scripts/yatt.lintrc") buffer))

(defun yatt-lint-any-handle-perl-action (buffer)
  (yatt-lint-any-perl-error-by
   (yatt-lint-cmdfile "scripts/yatt.lintany") buffer))

(defun yatt-lint-any-handle-perl-module (buffer)
  (yatt-lint-any-perl-error-by
   (yatt-lint-cmdfile "scripts/yatt.lintpm") buffer))

(defun yatt-lint-any-handle-perl-script (buffer)
  (yatt-lint-any-perl-error-by "perl -wc " buffer))

(defun yatt-lint-any-perl-error-by (command buffer)
  (plist-bind (rc err)
      (yatt-lint-any-shell-command command " " (buffer-file-name buffer))
    (when rc
      (let (match diag)
	(cond ((setq match
		     (yatt-lint-any-match
		      " at \\([^ ]*\\) line \\([0-9]+\\)[.,]"
		      err 'file 1 'line 2))
	       (setq diag (substring err 0 (plist-get match 'pos)))
	       )
	      ((setq match
		     (yatt-lint-any-match
		      "^\\([^\n]+\\)\n  loaded from \\(file '\\([^']+\\)'\\|(unknown file)\\)?"
		      err 'diag 1 'file 3))
	       (setq diag (plist-get match 'diag))
	       ))
	(append `(rc ,rc err ,(or diag err)) match)))))

;;========================================
;; Other utils
;;========================================
(defun yatt-lint-cmdfile (cmdfile &optional nocheck)
  (let ((cmd (concat (or (yatt-lint-any-find-driver)
			 yatt-lint-any-YATT-dir) "/" cmdfile)))
    (if (and (not nocheck)
	     (not (file-exists-p cmd)))
	(error "Can't find yatt command: %s" cmdfile))
    cmd))

(defun yatt-lint-any-shell-command (cmd &rest args)
  (let ((tmpbuf (generate-new-buffer " *yatt-lint-temp*"))
	rc err)
    (unwind-protect
	(setq rc (shell-command (apply #'concat cmd args) tmpbuf))
      (setq err (with-current-buffer tmpbuf
		  ;; To remove last \n
		  (goto-char (point-max))
		  (skip-chars-backward "\n")
		  (delete-region (point) (point-max))
		  (buffer-string)))
      ;; (message "error=(((%s)))" err)
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
