;; NOTE(law): Increase cursor speed w/ key repeat->fast & delay until repeat->short.
;; NOTE(law): Speed up emacs init time by wrapping this file with the following
;; let, which will exclude initial regexes:
;;
;; (let ((file-name-handler-alist nil)))

;;///////////////////////////////////////////////////////////////////////////////
;; Library Functions
;;///////////////////////////////////////////////////////////////////////////////

(defun law-create-emacs-path (dir-name)
  (concat user-emacs-directory
          (convert-standard-filename dir-name)))

(defun law-switch-to-minibuffer-window ()
  "Switch to minibuffer window (if active)"
  (interactive)
  (when (active-minibuffer-window)
    (select-frame-set-input-focus (window-frame (active-minibuffer-window)))
    (select-window (active-minibuffer-window))))

(defun law-split-window ()
  "Split the frame horizontally based on the frame's width."
  (interactive)
  (delete-other-windows)
  (message "frame width: %d\n" (frame-width))
  (let ((max-window-width 100))
    (dotimes (i (- (/ (frame-width) max-window-width) 1))
      (split-window-horizontally)))
  (balance-windows))

(defun law-set-frame-opacity (value)
  "Sets the transparency of the frame window. 0=transparent/100=opaque"
  (interactive "nSet frame opacity [0:100]:")
  (set-frame-parameter (selected-frame) 'alpha value))

(defun law-shorten-directory (dir max-length)
  "Show up to max-length of a directory name"
  (let ((path (reverse (split-string (abbreviate-file-name dir) "/")))
        (output ""))
    (when (and path (equal "" (car path)))
      (setq path (cdr path)))
    (while (and path (< (length output) (- max-length 4)))
      (setq output (concat (car path) "/" output))
      (setq path (cdr path)))
    (when path
      (setq output (concat ".../" output)))
    output))

(defun law-compilation-mode-hook ()
  (local-set-key (kbd "h") nil)
  ;; (setq compilation-finish-function 'law-highlight-error-lines)
  (setq truncate-lines nil) ;; automatically becomes buffer local
  (set (make-local-variable 'truncate-partial-width-windows) nil))

(defun law-rename-file-and-buffer (new-name)
  (interactive "sNew name: ")
  (let ((name (buffer-name))
        (filename (buffer-file-name)))
    (if (not filename)
        (message "Buffer '%s' is not visiting a file!" name)
      (if (get-buffer new-name)
          (message "A buffer named '%s' already exists!" new-name)
        (rename-file filename new-name 1)
        (rename-buffer new-name)
        (set-visited-file-name new-name)
        (set-buffer-modified-p nil)))))

(defun law-move-buffer-file (dir)
  (interactive "sNew directory: ")
  (let* ((name (buffer-name))
         (filename (buffer-file-name))
         (dir
          (if (string-match dir "\\(?:/\\|\\\\)$")
              (substring dir 0 -1) dir))
         (newname (concat dir "/" name)))

    (if (not filename)
        (message "Buffer '%s' is not visiting a file!" name)
      (copy-file filename newname 1)
      (delete-file filename)
      (set-visited-file-name newname)
      (set-buffer-modified-p nil)
      t)))

(defun law-fix-prog-mode ()
  ;; (if (bound-and-true-p law-mode)
  ;;    (font-lock-add-keywords nil law-mode-keywords)
  ;;  (font-lock-remove-keywords nil law-mode-keywords))

  ;; (if (fboundp 'font-lock-flush)
  ;;    (font-lock-flush)
  ;;  (when font-lock-mode
  ;;    (with-no-warnings (font-lock-fontify-buffer))))

  ;; (hs-minor-mode)
  (law-highlight-numbers)

  (font-lock-add-keywords nil
      '(("\\<\\(NOTE\\)" 1 'font-lock-note t)
        ("\\<\\(TODO\\)" 1 'font-lock-todo t)
        ("\\<\\(IMPORTANT\\)" 1 'font-lock-important t))))

(defun law-electrify-return-if-match (arg)
  (interactive "P")
  (let ((case-fold-search nil))
    (if (looking-at "[\]}\)\"]")
        (save-excursion (newline-and-indent)))
    (newline arg)
    (indent-according-to-mode)))

(defun law-insert-c-separator ()
  "Add a source code separator using a C-style comment."
  (interactive)
  (insert "\n/*")
  (insert-char ?/ (- fill-column 3))
  (insert "*/\n"))

(defun law-highlight-numbers ()
  (font-lock-add-keywords
   nil
   `(
     ;; Valid hex number (will highlight invalid suffix though)
     ("\\b0x[[:xdigit:]]+[uUlL]*\\b" . font-lock-string-face)

     ;; Invalid hex number
     ("\\b0x\\(\\w\\|\\.\\)+\\b" . font-lock-warning-face)

     ;; Valid floating point number.
     ("\\(\\b[0-9]+\\|\\)\\(\\.\\)\\([0-9]+\\(e[-]?[0-9]+\\)?\\([lL]?\\|[dD]?[fF]?\\)\\)\\b"
      (1 font-lock-string-face)
      (3 font-lock-string-face))

     ;; Invalid floating point number.  Must be before valid decimal.
     ("\\b[0-9].*?\\..+?\\b" . font-lock-warning-face)

     ;; Valid decimal number.  Must be before octal regexes otherwise 0 and 0l
     ;; will be highlighted as errors.  Will highlight invalid suffix though.
     ("\\b\\(\\(0\\|[1-9][0-9]*\\)[uUlL]*\\)\\b" 1 font-lock-string-face)

     ;; Valid octal number
     ("\\b0[0-7]+[uUlL]*\\b" . font-lock-string-face)

     ;; Floating point number with no digits after the period.  This must be
     ;; after the invalid numbers, otherwise it will "steal" some invalid
     ;; numbers and highlight them as valid
     ("\\b\\([0-9]+\\)\\." (1 font-lock-string-face))

     ;; Invalid number.  Must be last so it only highlights anything not
     ;; matched above.
     ("\\b[0-9]\\(\\w\\|\\.\\)+?\\b" . font-lock-warning-face))))

(require 'custom)

(defvar law-all-overlays ())

(defun law-delete-overlay (overlay is-after begin end &optional len)
  (delete-overlay overlay))

(defun law-highlight-current-line (bg-color)
  (interactive)
  (setq current-point (point))
  (beginning-of-line)
  (setq beg (point))
  (forward-line 1)
  (setq end (point))
  ;; Create and place the overlay
  (setq error-line-overlay (make-overlay 1 1))

  ;; Append to list of all overlays
  (setq law-all-overlays (cons error-line-overlay law-all-overlays))

  (overlay-put error-line-overlay
               'face '(background-color . ,bg-color))
  (overlay-put error-line-overlay
               'modification-hooks (list 'law-delete-overlay))
  (move-overlay error-line-overlay beg end)
  (goto-char current-point))

(defun law-delete-all-overlays ()
  (while law-all-overlays
    (delete-overlay (car law-all-overlays))
    (setq law-all-overlays (cdr law-all-overlays))))

(defun law-highlight-error-lines (compilation-buffer process-result)
  (interactive)
  (law-delete-all-overlays)
  (condition-case nil
      (while t
        (next-error)
        ;; (law-highlight-current-line "#101822")
        (save-excursion
          (compilation-next-error-function 0)
          (law-highlight-current-line "#101822")))
    (error nil)))

(defun law-fix-c-mode ()
  (interactive)

  ;; Indentation:
  (setq c-default-style "linux")
  (setq c-basic-offset 3)
  (setq comment-style 'indent)
  (setq comment-start "//")
  (setq comment-end "")
  (c-set-offset 'case-label '+)
  ;; (c-set-offset 'access-label 0)
  (c-set-offset 'arglist-intro '+)
  (c-set-offset 'label '+)
  (c-set-offset 'statement-cont 0)
  (c-set-offset 'statement-case-open 0)
  (c-set-offset 'substatement-case-open 0)
  (c-set-offset 'substatement-open 0)
  (c-set-offset 'inline-open 0)
  (c-set-offset 'case-open 0)
  ;; (c-set-offset 'cpp-macro 0)
  (c-set-offset 'arglist-close 0)
  (c-set-offset 'brace-list-open 0)
  (c-set-offset 'brace-list-intro '+)

  ;; Keys
  (local-set-key (kbd "C-c C-c") 'compile)
  (local-set-key (kbd "C-c -") 'law-insert-c-separator)
  ;; (local-set-key (kbd "RET") 'law-electrify-return-if-match)

  (modify-syntax-entry ?_ "w")

  (setq law-c-builtin '("global" "persist" "unit"))
  (setq law-c-equality '("===" "!==" "==" "!="))
  (setq law-c-operators '("+=" "-=" "->" "--" "++"
                          "*" "/" "~" "&" "|" "%" "+" "-"
                          "<" ">" "." "=" "," ";" "[" "]" "(" ")"))
  (setq law-c-types '("U8" "U16" "U32" "U64" "S8" "S16" "S32" "S64"
                      "B32" "F32" "F64" "Sz" "SSz" "USz"))

  (setq law-c-types-regex (regexp-opt law-c-types 'words))
  (setq law-c-builtin-regex (regexp-opt law-c-builtin 'words))
  (setq law-c-equality-regex (regexp-opt law-c-equality))


  (font-lock-add-keywords
   nil
   `((,law-c-equality-regex . 'font-lock-operator-face)
     ;; (,law-c-types-regex . 'font-lock-type-face)
     (,law-c-builtin-regex . 'font-lock-builtin-face)

     ;; TODO(law): Find ways to optimize all these.

     ;; TODO(law): The following does not account for assignments in single line
     ;; if expressions, i.e. if (...) foo = bar;

     ;; if|while (... = ...)
     ("\\(?:if\\|while\\)\\s-*\([^=<>\n]*\\(=\\)[^\n]*\n"
      (1 font-lock-negation-char-face))

     ;; struct|union|enum Foo
     ("^\\(?:struct\\|union\\|enum\\)\\s-+\\([_a-zA-Z][_a-zA-Z0-9]*\\)[\n;]"
      (1 font-lock-function-name-face))

     ;; typedef struct|union|enum Foo Foo;
     ("^typedef\\s-+\\(?:struct\\|union\\|enum\\)\\s-+\\([_a-zA-Z][_a-zA-Z0-9]*\\)\\s-+\\([_a-zA-Z][_a-zA-Z0-9]*\\);"
      ;; (1 font-lock-function-name-face)
      (2 font-lock-function-name-face))

     ;; typedef struct|union|enum Foo
     ("^typedef\\s-+\\(?:struct\\|union\\|enum\\)\\s-+\\([_a-zA-Z][_a-zA-Z0-9]*\\)\n"
      (1 font-lock-function-name-face))

     ;; } Foo;
     ("^}\\s-+\\([_a-zA-Z][_a-zA-Z0-9]*\\);"
      (1 font-lock-function-name-face))

     ;; #define foo(a) ...
     ("^#define\\s-+\\([_a-zA-Z][_a-zA-Z0-9\*]*\\)\\(\(\\)[^\)]*\\(\)\\)"
      (1 font-lock-function-name-face)  ;; function name
      (2 font-lock-function-name-face)  ;; open paren
      (3 font-lock-function-name-face)) ;; close paren

     ;; TODO(law): The next regex will fail with function pointer parameters -
     ;; find a way to properly balance parentheses. Commented version below
     ;; works for that case but fails on...

     ;; typedef DEBUG_PLATFORM_FREE_FILE(DebugPlatformFreeFile);

     ;; ...missing the closing parethesis.

     ;; static void foo (int a, int b)
     ("^\\b\\(?:[_a-zA-Z][_a-zA-Z0-9\*]*\\s-+\\)*\\([_a-zA-Z][_a-zA-Z0-9]*\\)\\(\(\\)[^\)]*\\(\)\\)"
      ;;"^\\b\\(?:[_a-zA-Z][_a-zA-Z0-9\*]*\\s-+\\)*\\([_a-zA-Z][_a-zA-Z0-9]*\\)\\(\(\\)[^\{]*\\(\)\\)"
      (1 font-lock-function-name-face)    ;; function name
      (2 font-lock-function-name-face)    ;; open paren
      (3 font-lock-function-name-face)))) ;; close paren

  (message "c-mode was fixed\n"))

(defun law-fix-sh-mode ()
  (local-set-key (kbd "C-c C-c") 'compile))

(defun law-fix-html-for-work ()
  (setq indent-tabs-mode t)
  (setq-default tab-width 2)
  (setq comment-start "<!---")
  (setq comment-end "--->"))

(defun law-fix-js-for-work ()
  (setq indent-tabs-mode t)
  (setq-default tab-width 2))

(defun law-autoinsert-templates ()
  (define-auto-insert
    '("\\.bat\\'" . "Batch file skeleton")
    '(nil
      "@echo off\n"
      "\n"
      "set compiler_flags=-nologo -Z7 -Od\n"
      "set linker_flags=-incremental:no\n"
      "\n"
      "cl " _ " %compiler_flags% /link %linker_flags%\n"
      "\n"
      ))

  (define-auto-insert
    '("\\.\\(CC?\\|cc\\|cxx\\|cpp\\|c++\\|c\\|m\\)\\'" . "C/C++ skeleton")
    '(nil
      "/*/////////////////////////////////////////////////////////////////////////////*/\n"
      "/* (c) copyright " (format-time-string "%Y")
      " Lawrence D. Kern ////////////////////////////////////////*/\n"
      "/*/////////////////////////////////////////////////////////////////////////////*/\n\n"
      _))

  (define-auto-insert
    '("\\.\\(HH?\\|hh\\|hxx\\|hpp\\|h++\\|h\\)\\'" . "Header skeleton")
    '(nil
      "#if !defined("
      (upcase (file-name-nondirectory (file-name-sans-extension buffer-file-name)))
      "_H)\n"
      "/*/////////////////////////////////////////////////////////////////////////////*/\n"
      "/* (c) copyright " (format-time-string "%Y")
      " Lawrence D. Kern ////////////////////////////////////////*/\n"
      "/*/////////////////////////////////////////////////////////////////////////////*/\n\n"
      _ "\n\n"
      "#define " (upcase (file-name-nondirectory (file-name-sans-extension buffer-file-name))) "_H\n"
      "#endif"))

  (define-auto-insert
    '("\\.\\(d\\)\\'" . "D module skeleton")
    '(nil
      "/*/////////////////////////////////////////////////////////////////////////////*/\n"
      "/* (c) copyright " (format-time-string "%Y")
      " Lawrence D. Kern ////////////////////////////////////////*/\n"
      "/*/////////////////////////////////////////////////////////////////////////////*/\n\n"
      "module "
      (file-name-nondirectory (file-name-sans-extension buffer-file-name))
      ";\n"
      _ "\n\n")))


;;///////////////////////////////////////////////////////////////////////////////
;; Font-lock Faces
;;///////////////////////////////////////////////////////////////////////////////

(defface font-lock-operator-face
  '((t (:foreground "blue")))
  "Basic face for operators."
  :group 'basic-faces)

(defface font-lock-note
  '((t (:foreground "green" :underline t)))
  "NOTE comment highlighting"
  :group 'basic-faces)

(defface font-lock-todo
  '((t (:foreground "red" :underline t)))
  "TODO comment highlighting"
  :group 'basic-faces)

(defface font-lock-important
  '((t (:foreground "yellow" :underline t)))
  "IMPORTANT comment highlighting"
  :group 'basic-faces)


;;///////////////////////////////////////////////////////////////////////////////
;; General Configuration
;;///////////////////////////////////////////////////////////////////////////////

(setq law-macos  (eq system-type 'darwin))
(setq law-linux  (eq system-type 'gnu/linux))
(setq law-win32  (eq system-type 'windows-nt))
(setq law-cygwin (eq system-type 'cygwin))

(setq law-work-code-style nil)

(setq mode-line-format (list
       mode-line-front-space
       mode-line-mule-info
       mode-line-client
       mode-line-modified
       mode-line-remote
       mode-line-frame-identification
       mode-line-buffer-identification
       "   "
       mode-line-position
       "   "
       "("
       ;; mode-line-modes
       '(:eval mode-name)
       ")"
       "   "
       '(vc-mode vc-mode)
       mode-line-misc-info
       ;; evil-mode-line-tag
       mode-line-end-spaces))

(setq-default mode-line-format mode-line-format)

(blink-cursor-mode -1)
(menu-bar-mode -1)
(tool-bar-mode -1)
(scroll-bar-mode -1)
(tooltip-mode -1)
(global-hl-line-mode -1)

(show-paren-mode 1)
(auto-insert-mode t)
(column-number-mode)

;; (abbrev-mode 1)
;; (global-undo-tree-mode nil)

;; (setq initial-scratch-message ";; Lisp *scratch* Buffer\n\n")
(setq compilation-ask-about-save nil)
(setq truncate-partial-width-windows t)
(setq ad-redefinition-action 'accept)
(setq ring-bell-function 'ignore)
(setq inhibit-splash-screen t)
(setq global-linum-mode nil)
(setq make-backup-files nil)
(setq auto-save-default nil)
(setq undo-limit 20000000)
(setq undo-strong-limit 40000000)
(setq scroll-conservatively 10000)
(setq scroll-preserve-screen-position t)
;;(setq hscroll-step 1)
(setq gdb-many-windows nil)
(setq gdb-show-main t)
(setq compilation-skip-threshold 1)
(setq compilation-context-lines 0)
(setq dabbrev-case-replace t)
(setq dabbrev-case-fold-search t)
(setq dabbrev-upcase-means-case-search t)
(setq split-window-preferred-function nil)
(setq split-width-threshold 0)
(setq split-height-threshold nil)
(setq show-paren-delay 0)
(setq gc-cons-threshold 1600000)
(setq use-package-always-ensure t)
;; (setq same-window-regexps '("."))
(setq same-window-regexps nil)
(setq font-lock-maximum-decoration 1)
;; (setq font-lock-maximum-decoration '((c-mode . l) (c++-mode . 1) (t . t)))
(setq org-export-dispatch-use-expert-ui 1)

(setq cperl-indent-level 2)
(setq javascript-indent-level 2)
(setq js-indent-level 2)
(setq js-switch-indent-offset 2)
(setq js2-indent-level 2)
(setq css-indent-offset 2)

(setq-default fill-column 80)
(setq-default indent-tabs-mode nil)
(setq-default tab-width 8)

;; M-x shell should affect the currently-active window
(push (cons "\\*shell\\*" display-buffer--same-window-action) display-buffer-alist)

(fset 'yes-or-no-p 'y-or-n-p)

(set-frame-parameter nil 'scroll-bar-background nil)
(windmove-default-keybindings)

(set-default 'truncate-lines t)
(set 'gdb-use-separate-io-buffer nil)
;; (fringe-mode nil)

(set-variable 'grep-command "grep -irHn ")

(global-set-key (kbd "C-z") nil)
(global-set-key (kbd "C-x C-z") nil)

(global-set-key (kbd "C-;") 'execute-extended-command)
(global-set-key (kbd "C-,") 'other-window)

(global-set-key (kbd "C-c r") 'query-replace)
(global-set-key (kbd "C-c s") 'ff-find-other-file)
(global-set-key (kbd "C-c c") 'compile)
(global-set-key (kbd "C-c e") 'eval-buffer)
(global-set-key (kbd "C-c f") 'find-file-other-window)

;; (global-set-key (kbd "C-c i") 'hs-hide-block)
;; (global-set-key (kbd "C-c o") 'hs-show-block)
;; (global-set-key (kbd "C-c h") 'hs-hide-all)
;; (global-set-key (kbd "C-c o") 'hs-show-all)

;; (global-set-key (kbd "C-c g") 'magit-status)
;; (global-set-key (kbd "C-c M-g") 'magit-dispatch-popup)

;; (global-set-key (kbd "C-c h") 'windmove-left)
;; (global-set-key (kbd "C-c j") 'windmove-down)
;; (global-set-key (kbd "C-c k") 'windmove-up)
;; (global-set-key (kbd "C-c l") 'windmove-right)

(global-set-key (kbd "<f5>") 'recompile)
(global-set-key (kbd "<f7>") 'law-switch-to-minibuffer-window)

(global-set-key (kbd "<backspace>") 'ignore)
(global-set-key (kbd "C-h h") 'ignore)
(define-key minibuffer-local-map (kbd "C-h") 'backward-delete-char)

(setq law-font
      (cond
       ((member "Essential PragmataPro" (font-family-list)) "Essential PragmataPro-9")
       ((member "Iosevka"               (font-family-list)) "Iosevka-9")
       ((member "Fira Code"             (font-family-list)) "Fira Code-9")
       ((member "ProggyCleanTTSZ"       (font-family-list)) "ProggyCleanTTSZ-12:antialias=none")
       ((member "Px437 ATI 8x16"        (font-family-list)) "Px437 ATI 8x16-16")
       ((member "Px437 ATI 8x8-2y"      (font-family-list)) "Px437 ATI 8x8-2y-12")
       ((member "Input"                 (font-family-list)) "Input-11")
       ((member "Source Code Pro"       (font-family-list)) "Source Code Pro-10")
       ((member "Meslo LG M"            (font-family-list)) "Meslo LG M-12")
       (t "monospace")))

(setq line-spacing nil)
(set-frame-font law-font nil)
(add-to-list 'default-frame-alist `(font . ,law-font))

(when law-win32
  (setq compile-command "build.bat")
  (setq python-shell-interpreter "c:\\Python\\python.exe")
  (setq exec-path (append exec-path '("C:\\Python\\;")))
  ;; (setenv "PATH" (concat "c:\\Cygwin64\\bin;" (getenv "PATH")))
  (set-variable 'grep-command "findstr -s -n -i -l "))

(when law-cygwin
  (setq compile-command "build.bat")
  (setenv "HOME" "/home/law")
  (let ((shellname "/bin/bash"))
    (setenv "ESHELL" shellname)
    (setenv "SHELL" shellname)
    (setq shell-file-name shellname))

  (load "comint")
  (setq comint-completion-addsuffix t)
  (setq comint-eol-on-send t)
  (setq law-font "Source Code Pro-9"))

(when law-macos
  (setq compile-command "sh build.sh")
  (setq mac-command-modifier 'meta)
  (setq mac-pass-command-to-system nil)
  (setq mac-command-key-is-meta t
        exec-path (append exec-path '("/usr/local/bin:/Users/law/.cargo/bin"))
        inferior-lisp-program "/applications/lang/cmucl/bin/lisp"
        geiser-racket-binary "/applications/lang/racket/bin/racket"
        slime-contribs '(slime-fancy))

  (add-to-list 'default-frame-alist '(ns-transparent-titlebar . t))
  (add-to-list 'default-frame-alist '(ns-appearance . dark))
  (setq ns-use-proxy-icon  nil)
  (setq frame-title-format nil)
  (setq ns-use-native-fullscreen nil)


  (setq slime-lisp-implementations
        '((cmucl ("/applications/lang/cmucl/bin/lisp"))
          (sbcl ("sbcl"))))

  (setenv "PATH"
          (concat (getenv "PATH")
                  ":/usr/local/bin:/Users/law/.cargo/bin:/Library/TeX/texbin")))

(when law-work-code-style
  (add-hook 'js2-mode-hook 'law-fix-js-for-work)
  (add-hook 'html-mode-hook 'law-fix-html-for-work))

(add-to-list 'comint-output-filter-functions 'ansi-color-process-output)

(setq inferior-js-program-command "node --interactive")
(setenv "NODE_NO_READLINE" "1")

;; (add-to-list 'tooltip-frame-parameters '(internal-border-width . 10))
;; (add-to-list 'tooltip-frame-parameters '(border-width . 0))

(setq tooltip-frame-parameters
      '((border-width . 3)
        (internal-border-width . 10)
        (name . "tooltip")
        (no-special-glyphs . t)))

(setq whitespace-style
      '(face spaces tabs newline space-mark tab-mark newline-mark))

(setq whitespace-display-mappings
      '((space-mark 32 [183] [46])
        (newline-mark 10 [? 8629 10]) ;[8629 10]
        (tab-mark 9 [8594 9] [92 9])))

;; (setq fixme-modes '(law-mode))
;; bury *scratch* buffer instead of killing it
(defadvice kill-buffer (around kill-buffer-around-advice activate)
  (let ((buffer-to-kill (ad-get-arg 0)))
    (if (equal buffer-to-kill "*scratch*")
        (bury-buffer)
      ad-do-it)))

;; Inscrutable fix for jumping to compile errors in Clang:
(require 'compile)
(nth 5 (assoc 'gcc-include compilation-error-regexp-alist-alist)) ; (4 . 5)
(setf (nth 5 (assoc 'gcc-include compilation-error-regexp-alist-alist)) 0)

;; Fix for D compile errors:
(add-to-list
 'compilation-error-regexp-alist-alist
 '(dmd "^\\([^ \n]+\\)(\\([0-9]+\\)): \\(?:error\\|.\\|warnin\\(g\\)\\|remar\\(k\\)\\)"
   1 2 nil (3 . 4)))

(add-to-list 'compilation-error-regexp-alist 'dmd)

;; Fix for MSVC compile errors with column numbers enabled:
(add-to-list
 'compilation-error-regexp-alist-alist
 '(msvc "^\\([^\t\n]+\\)(\\([0-9]+\\),\\([0-9]+\\)): \\(?:error\\|warnin\\(g\\)\\|remar\\(k\\)\\)"
        1 2 3 (4 . 5)))

(add-to-list 'compilation-error-regexp-alist 'msvc)

(add-to-list 'auto-mode-alist '("\\.metal\\'" . c++-mode))
(add-to-list 'auto-mode-alist '("\\.cfm\\'" . html-mode))
(add-to-list 'auto-mode-alist '("\\.cfc\\'" . js-mode))

(add-hook 'before-save-hook 'delete-trailing-whitespace)
(add-hook 'c-mode-common-hook 'law-fix-c-mode)
(add-hook 'compilation-mode-hook 'law-compilation-mode-hook)
(add-hook 'prog-mode-hook 'law-fix-prog-mode)
(add-hook 'shell-mode-hook 'ansi-color-for-comint-mode-on)
(add-hook 'sh-mode-hook #'law-fix-sh-mode)
(add-hook 'after-init-hook 'law-autoinsert-templates)


;;///////////////////////////////////////////////////////////////////////////////
;; Initialization
;;///////////////////////////////////////////////////////////////////////////////

(add-to-list 'load-path (law-create-emacs-path "evil/"))
(add-to-list 'load-path (law-create-emacs-path "themes/"))
(add-to-list 'custom-theme-load-path (law-create-emacs-path "themes/"))

(load-theme 'glacier t t)
(load-theme 'black-ice t nil)

(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
;; (add-to-list 'package-archives '("marmalade" . "http://marmalade-repo.org/packages/") t)
;; (add-to-list 'package-archives '("gnu" . "http://elpa.gnu.org/packages/") t)
;; (add-to-list 'package-archives '("org" . "http://orgmode.org/elpa/") t)

(package-initialize)

(unless package-archive-contents
  (package-refresh-contents))

(unless (package-installed-p 'use-package)
  (package-install 'use-package))

(require 'use-package)
(require 'evil)

(evil-mode 1)
(setq evil-toggle-key "")

(use-package ivy :ensure
  :bind (:map ivy-minibuffer-map
              ("C-h" . ivy-backward-delete-char)
              ("C-j" . ivy-next-line)
              ("C-k" . ivy-previous-line)
              ("C-l" . ivy-alt-done)
              ("RET" . ivy-alt-done))
  :init (ivy-mode 1)
  :config
  (setq ivy-use-virtual-buffers t)
  (setq ivy-height 25)
  (setq ivy-count-format "(%d/%d) ")
  (setq ivy-extra-directories nil))

(use-package counsel-etags
  :config
  (setq tags-revert-without-query t)
  (setq large-file-warning-threshold nil)
  (advice-add 'evil-goto-definition :override 'counsel-etags-find-tag-at-point)
  (add-hook 'prog-mode-hook
            (lambda ()
              (add-hook 'after-save-hook
                        'counsel-etags-virtual-update-tags 'append 'local))))

(use-package paredit :ensure
  :bind (("RET" . law-electrify-return-if-match))
  :hook ((emacs-lisp-mode lisp-mode clojure-mode lisp-interaction-mode scheme-mode)
         . paredit-mode)
  :config (paredit-mode t))

(set-frame-parameter nil 'fullscreen 'fullboth)
(law-split-window)


(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(global-auto-revert-mode t)
 '(global-visible-mark-mode t)
 '(package-selected-packages
   (quote
    (counsel-etags htmlize undo-tree markdown-mode evil paredit ivy use-package)))
 '(safe-local-variable-values (quote ((Lexical-binding . t)))))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
