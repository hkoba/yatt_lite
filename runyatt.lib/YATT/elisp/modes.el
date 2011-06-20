;;
;;
;;
(add-to-list 'load-path
	     (file-name-directory load-file-name))

(autoload 'yatt-mode "yatt-mode"
  "YATT mode" t)

(defvar yatt-mode-file-coding 'utf-8-dos "file coding for yatt files.")

(let ((yatt-ext "\\.\\(yatt\\|ytmpl\\)\\'"))

  (add-to-list 'auto-mode-alist `(,yatt-ext . yatt-mode))
  (add-to-list 'auto-mode-alist '("\\.ydo\\'" . cperl-mode))

  (add-to-list 'file-coding-system-alist
	       `(,yatt-ext . ,yatt-mode-file-coding)))

;;
(autoload 'yatt-lint-any-mode "yatt-lint-any-mode"
  "auto lint for yatt and others." t)

(autoload 'yatt-lint-any-mode-check-blacklist "yatt-lint-any-mode"
  "To avoid yatt-lint." t)

(add-hook 'cperl-mode-hook
	  '(lambda () (or (yatt-lint-any-mode-check-blacklist)
			  (yatt-lint-any-mode t))))

;;
(autoload 'plist-bind "yatt/utils" "plist alternative of multivalue-bind" t)
