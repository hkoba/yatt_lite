;;; lsp-yatt --- YATT::Lite support for lsp-mode -*- lexical-binding: t -*-

;;; Copyright (C) 2019 KOBAYASI Hiroaki

;; Author: KOBAYASI Hiroaki <hkoba@cpan.org>


;;; Commentary:

;;; Code:

(require 'lsp-mode)
(require 'yatt-lint-any-mode)

(defconst lsp-yatt--get-root
  (lsp-make-traverser #'(lambda (dir)
                          (directory-files dir nil "app.psgi"))))

(defun lsp-yatt--ls-command ()
  "Generate the language server startup command."
  (let* ((app-dir (locate-dominating-file "." "app.psgi"))
         (yatt-lib (cond (app-dir
                          (concat app-dir "lib/YATT/"))
                         (t
                          yatt-lint-any-YATT-dir))))
    (list (concat yatt-lib "Lite/LanguageServer.pm") "server")))

(lsp-define-stdio-client
 lsp-yatt "yatt"
 lsp-yatt--get-root
 nil
 ;; :initialize 'lsp-yatt--initialize-client
 :command-fn 'lsp-yatt--ls-command)

(provide 'lsp-yatt)
;;; lsp-yatt.el ends here
