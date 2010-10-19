;;; yatt-mode.el -- Major mode to edit yatt templates.

;;; Copyright (C) 2010 KOBAYASI Hiroaki

;; Author: KOBAYASI Hiroaki <hkoba@cpan.org>

;;
;; To use yatt-mode, add followings to your .emacs:
;;
;; (autoload 'yatt-mode "yatt-mode")
;; (add-to-list 'auto-mode-alist '("\\.\\(yatt\\|ytmpl\\)\\'" . yatt-mode))
;; (add-to-list 'auto-mode-alist '("\\.ydo\\'" . perl-mode))
;;

(require 'mmm-mode)
(require 'derived)
(require 'sgml-mode)

(require 'yatt-lint-any-mode)

(defvar yatt-mode-hook nil
  "yatt �ǽ񤫤줿�ƥ�ץ졼�Ȥ��Խ����뤿��Υ⡼��")

(defvar yatt-mode-YATT-dir
  (if load-file-name
      (file-name-directory
       (directory-file-name
	(file-name-directory
	 (file-truename load-file-name)))))
  "Where YATT is installed. This is used to locate ``yatt.lint''.")

;;========================================
;; �̾�� html ��ʬ
(define-derived-mode yatt-mode html-mode "YATT"
  "yatt:* �����Τ��� html �ե�������Խ����뤿��Υ⡼��"
  ;; To avoid duplicate call from mmm-mode-on (mmm-update-mode-info)
  (unless (yatt-mode-called-from-p 'mmm-mode-on)
    ;;
    (setq mmm-classes '(yatt-declaration html-js embedded-css))
    (setq mmm-submode-decoration-level 2)
    (make-variable-buffer-local 'process-environment)
    (yatt-lint-any-mode 1)
    (yatt-mode-ensure-file-coding)
    (mmm-mode-on)
    ;; cperl-mode �ˤ�����ǡ� buffer-modified-p ��Ω�äƤ�... ���Ȼפ�����...
    ;; ʬ�����
    ;; [after idle] Ū�ʽ�����ɬ�פʤ�Ǥ�?
    (yatt-mode-multipart-refontify)
    (run-hooks 'yatt-mode-hook)))

(define-derived-mode yatt-declaration-mode html-mode "YATT decl"
  "yatt:* �����Ρ������ʬ")

;;----------------------------------------
(defface yatt-declaration-submode-face
  '((t (:background "#d2d4f1")))
  "Face used for yatt declaration block (<!yatt:...>)")

(defface yatt-action-submode-face
  '((t (:background "#f4f2f5")))
  "Face used for yatt action part (<!yatt:...>)")

;; html ����Ρ� <!yatt:...> ���̤��� yatt-declaration-mode �ء�
(mmm-add-classes
 '((yatt-declaration
    :submode yatt-declaration-mode
    :face yatt-declaration-submode-face
    :include-front t :include-back t
    :front "^<![a-z]+:"
    :back ">\n")))

;;========================================
(defun yatt-mode-multipart-refontify ()
  (interactive)
  (let ((modified (buffer-modified-p))
	(fn (buffer-file-name))
	sym start finish)
    (dolist (part (yatt-mode-multipart-list))
      (setq sym (car part) start (cadr part) finish (caddr part))
      (case sym
	(!yatt:widget)
	(!yatt:action
	 ;; XXX: mmm-ify-region ���ɤ��ʤ����⡣ interactive ���ȡ�
	 (mmm-make-region 'cperl-mode start finish
			  :face 'yatt-action-submode-face)
	 (mmm-enable-font-lock 'cperl-mode))))
    (mmm-refontify-maybe)
    (when (and (not modified)
	       (eq (file-locked-p fn) t))
      (message "removing unwanted file lock from %s" fn)
      (restore-buffer-modified-p t)
      (unlock-buffer)
      (restore-buffer-modified-p nil))))

(defun yatt-mode-multipart-list ()
  (do* (result
	(regions (mmm-regions-in (point-min) (point-max))
		 next)
	(reg (car regions) (car regions))
	(next (cdr regions) (cdr regions))
	(section `(default ,(cadr (car regions))))
	reg)
      ;; ����̵���ʤ顢�Ǹ�� section ��ͤ���֤�
      ((not next)
       (reverse (cons (append section (list (caddr reg))) result)))
    (when (eq (car reg) 'yatt-declaration-mode)
      (setq begin (cadr reg) end (caddr reg)
	    ;; �����ޤǤ���Ͽ���Ĥġ�
	    result (cons (append section (list begin))
			 result)
	    ;; ������ section ��Ϥ��
	    section (list (yatt-mode-decltype reg) end)))))

(defun yatt-mode-decltype (region)
  (let* ((min (cadr region)) (max (caddr region))
	 (start (next-single-property-change min 'face (current-buffer) max))
	 (end (next-single-property-change start 'face (current-buffer) max)))
    ;; XXX: !yatt: �ǻϤޤ�ʤ��ä���?
    (intern (buffer-substring-no-properties start end))))

;;========================================

(defun yatt-mode-ensure-file-coding (&optional new-coding)
  (let ((modified (buffer-modified-p))
	(old-coding buffer-file-coding-system))
    (setq new-coding (or new-coding yatt-mode-file-coding))
    (when (and new-coding
	       (not (eq old-coding new-coding)))
      (set-buffer-file-coding-system new-coding nil)
      (set-buffer-modified-p modified)
      (message "coding is changed from %s to %s, modified is now %s"
	       old-coding new-coding modified))))

;;========================================
;; Debugging aid.

(defun yatt-mode-called-from-p (fsym)
  (do* ((i 0 (1+ i))
	(frame (backtrace-frame i) (backtrace-frame i)))
      ((not frame))
    (when (eq (cadr frame) fsym)
      (return t))))

(defun yatt-mode-from-hook-p (hooksym)
  (do* ((i 0 (1+ i))
	(frame (backtrace-frame i) (backtrace-frame i)))
      ((not frame))
    (when (and (eq (cadr frame) 'run-hooks)
	       (eq (caddr frame) hooksym))
      (return t))))

(defun yatt-mode-backtrace (msg &rest args)
  (let ((standard-output (get-buffer-create "*yatt-debug*")))
    (princ "---------------\n")
    (princ (apply 'format msg args))
    (princ "\n---------------\n")
    (backtrace)
    (princ "\n\n")))
