;;
;;
;;
(add-to-list 'load-path
	     (file-name-directory load-file-name))

(autoload 'yatt-mode "yatt-mode"
  "YATT mode" t)

(autoload 'yatt-lint-any-mode "yatt-lint-any-mode"
  "auto lint for yatt and others." t)

(add-to-list 'auto-mode-alist '("\\.\\(yatt\\|ytmpl\\)\\'" . yatt-mode))
(add-to-list 'auto-mode-alist '("\\.ydo\\'" . perl-mode))

(autoload 'plist-bind "yatt/utils" "plist alternative of multivalue-bind" t)
