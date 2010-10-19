;;
;;
;;
(add-to-list 'load-path
	     (file-name-directory load-file-name))

(autoload 'yatt-mode "yatt-mode"
  "YATT mode" t)

(add-to-list 'auto-mode-alist '("\\.\\(yatt\\|ytmpl\\)\\'" . yatt-mode))
(add-to-list 'auto-mode-alist '("\\.ydo\\'" . cperl-mode))

(defvar yatt-mode-file-coding 'utf-8-dos "file coding for yatt files.")

(add-to-list 'file-coding-system-alist
	     `("\\.yatt\\'" . ,yatt-mode-file-coding))

;;
(autoload 'yatt-lint-any-mode "yatt-lint-any-mode"
  "auto lint for yatt and others." t)

(add-hook 'cperl-mode-hook
	  '(lambda () (yatt-lint-any-mode t)))

;;
(autoload 'plist-bind "yatt/utils" "plist alternative of multivalue-bind" t)
