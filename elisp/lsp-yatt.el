;;; lsp-yatt --- YATT::Lite support for lsp-mode -*- lexical-binding: t -*-

;;; Copyright (C) 2019 KOBAYASI Hiroaki

;; Author: KOBAYASI Hiroaki <hkoba@cpan.org>


;;; Commentary:

;;; Code:

(require 'lsp-mode)
(require 'yatt-lint-any-mode)

(defun lsp-yatt--ls-command ()
  "Generate the language server startup command."
  (let* ((app-dir (locate-dominating-file "." "app.psgi"))
         (yatt-lib (cond (app-dir
                          (concat app-dir "lib/YATT/"))
                         (t
                          yatt-lint-any-YATT-dir))))
    (list (concat yatt-lib "Lite/LanguageServer.pm") "server")))

(lsp-register-client
 (make-lsp-client :new-connection (lsp-stdio-connection 'lsp-yatt--ls-command)
                  :major-modes '(yatt-mode)
                  :server-id 'yatt))

(provide 'lsp-yatt)
;;; lsp-yatt.el ends here
