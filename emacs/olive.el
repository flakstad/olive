;;; olive.el --- Scratch Odin probing helpers -*- lexical-binding: t; -*-
;; Copyright (c) Andreas Flakstad and Olive contributors
;; SPDX-License-Identifier: MIT

;; This is intentionally small: it shells out to the olive CLI, displays
;; results in Emacs buffers, and leaves Odin semantics to Odin itself.

(require 'compile)
(require 'json)
(require 'seq)
(require 'subr-x)

(defgroup olive nil
  "Scratch execution helpers for Odin."
  :group 'languages)

(defcustom olive-command "olive"
  "Fallback compiled olive executable."
  :type 'string
  :group 'olive)

(defcustom olive-root
  (file-name-directory (directory-file-name
                        (file-name-directory (or load-file-name buffer-file-name default-directory))))
  "Path to the local olive checkout."
  :type 'directory
  :group 'olive)

(defcustom olive-result-buffer-name "*Olive*"
  "Buffer name used for olive command output."
  :type 'string
  :group 'olive)

(defcustom olive-inline-result-prefix "=> "
  "Prefix used for inline olive result overlays."
  :type 'string
  :group 'olive)

(defcustom olive-runner-buffer-name "*Olive Generated*"
  "Buffer name used for generated Odin when `olive-show-generated' is non-nil."
  :type 'string
  :group 'olive)

(defcustom olive-reload-buffer-name "*Olive Reload*"
  "Buffer name prefix used for live hot-reload command output."
  :type 'string
  :group 'olive)

(defcustom olive-run-buffer-name "*Odin Run*"
  "Buffer name used for live `odin run' command output."
  :type 'string
  :group 'olive)

(defcustom olive-show-generated nil
  "When non-nil, request and display generated Odin before command output."
  :type 'boolean
  :group 'olive)

(defcustom olive-default-no-print nil
  "When non-nil, default olive commands run snippets as statements."
  :type 'boolean
  :group 'olive)

(defcustom olive-test-after-build nil
  "When non-nil, run `odin test .' after a successful package build."
  :type 'boolean
  :group 'olive)

(defcustom olive-test-args '("-define:ODIN_TEST_LOG_LEVEL=warning")
  "Extra args passed to `odin test .' by Olive test commands.
The default suppresses the verbose successful test-runner info logs while still
showing warnings, errors, and the final test summary."
  :type '(repeat string)
  :group 'olive)

(defvar olive--last-source-buffer nil)

(defun olive-clear-inline-results ()
  "Delete olive inline result overlays in the current buffer."
  (remove-overlays (point-min) (point-max) 'olive-result-overlay t))

(defun olive--enable-inline-result-clearing ()
  "Clear olive inline overlays before the next command in this buffer."
  (add-hook 'pre-command-hook #'olive-clear-inline-results nil t))

(defun olive--project-root (&optional start)
  "Return a likely Odin project root for START or the current buffer."
  (let* ((path (cond
                ((bufferp start) (or (buffer-file-name start) default-directory))
                ((stringp start) start)
                ((buffer-file-name) (buffer-file-name))
                (t default-directory)))
         (dir (if (and path (file-directory-p path))
                  path
                (file-name-directory (expand-file-name path)))))
    (let ((find-entry-point-dir
           (lambda (directory)
             (let ((current (file-name-as-directory (expand-file-name directory)))
                   (found nil))
               (while (and current (not found))
                 (when (olive--directory-has-entry-point-p current)
                   (setq found current))
                 (let ((parent (file-name-directory (directory-file-name current))))
                   (if (or (null parent) (string= parent current))
                       (setq current nil)
                     (setq current parent))))
               found))))
      (or (locate-dominating-file dir "ols.json")
          (locate-dominating-file dir "odin.json")
          (funcall find-entry-point-dir dir)
          (locate-dominating-file dir ".git")
          dir))))

(defun olive-package-directory ()
  "Return the Odin package directory for the current buffer.
For Odin this is usually the directory containing the current file."
  (if buffer-file-name
      (file-name-directory (expand-file-name buffer-file-name))
    default-directory))

(defun olive--directory-has-entry-point-p (directory)
  "Return non-nil when DIRECTORY contains a package `main` with `main :: proc`."
  (seq-some
   (lambda (path)
     (with-temp-buffer
       (insert-file-contents path)
       (and (re-search-forward "^[[:space:]]*package[[:space:]]+main\\b" nil t)
            (re-search-forward "^[[:space:]]*main[[:space:]]*::[[:space:]]*proc\\b" nil t))))
   (directory-files directory t "\\.odin\\'")))

(defun olive-project-directory ()
  "Return the current Odin project directory."
  (file-name-as-directory (olive--project-root)))

(defun olive--cli-args (command package code &optional no-print show internal save generated)
  "Return olive CLI args for COMMAND, PACKAGE, and CODE."
  (append
   (list "eval" package code)
   (when (string= command "check") (list "--check"))
   (when no-print (list "--no-print"))
   (when show (list "--show"))
   (when internal (list "--internal"))
   (when save (list "--save" save))
   (when generated (list "--generated" generated))))

(defun olive--compiled-command ()
  "Return the compiled olive executable, or nil."
  (let* ((root (file-name-as-directory (expand-file-name olive-root)))
         (local (expand-file-name "olive" root)))
    (cond
     ((file-executable-p local) local)
     ((executable-find olive-command) (executable-find olive-command))
     (t nil))))

(defun olive--compiled-command-or-error ()
  "Return the compiled olive executable or signal a user-facing error."
  (or (olive--compiled-command)
      (user-error "Compiled olive CLI not found; run `odin build cmd/olive`")))

(defun olive--process-command (args)
  "Return a process command for olive ARGS."
  (cons (olive--compiled-command-or-error) args))

(defun olive--read-generated-file (path)
  "Return generated Odin from PATH, deleting PATH when possible."
  (when (and path (file-exists-p path))
    (unwind-protect
        (with-temp-buffer
          (insert-file-contents path)
          (buffer-string))
      (ignore-errors
        (delete-file path)))))

(defun olive--prepare-buffer (name)
  "Create and clear buffer NAME."
  (let ((buffer (get-buffer-create name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (special-mode)
        (setq-local truncate-lines nil)
        (setq-local word-wrap t)
        (visual-line-mode 1)))
    buffer))

(defun olive--split-generated-output (text)
  "Split TEXT from `--show' into (GENERATED . OUTPUT).
This relies on generated programs ending before the first Odin compiler/runtime
output. It is deliberately best-effort; if splitting is unclear, all text is
treated as command output."
  (if (string-match "\nmain :: proc() {\n" text)
      (let ((last-brace (string-match "\n}\n" text)))
        (if last-brace
            (cons (substring text 0 (match-end 0))
                  (substring text (match-end 0)))
          (cons nil text)))
    (cons nil text)))

(defun olive--visible-output (stdout stderr show-generated)
  "Return (GENERATED . VISIBLE-OUTPUT) from STDOUT and STDERR."
  (let* ((split (and show-generated (olive--split-generated-output stdout)))
         (generated (car-safe split))
         (visible-stdout (if split (cdr split) stdout))
         (visible (string-trim
                   (concat visible-stdout
                           (unless (or (string-empty-p visible-stdout)
                                       (string-empty-p stderr))
                             "\n")
                           stderr))))
    (cons generated visible)))

(defun olive--show-inline-result (buffer beg end text exit-code)
  "Show TEXT inline in BUFFER after BEG and END."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (remove-overlays beg end 'olive-result-overlay t)
      (let* ((trimmed (string-trim text))
             (display-text (if (string-empty-p trimmed)
                               (format " %s<exit %s>" olive-inline-result-prefix exit-code)
                             (format " %s%s" olive-inline-result-prefix
                                     (replace-regexp-in-string "[\n\r\t ]+" " " trimmed))))
             (ov (make-overlay beg end)))
        (put-text-property 0 1 'cursor 0 display-text)
        (put-text-property 0 (length display-text) 'face
                           (if (zerop exit-code) 'shadow 'error)
                           display-text)
        (overlay-put ov 'olive-result-overlay t)
        (overlay-put ov 'priority 1000)
        (overlay-put ov 'evaporate t)
        (overlay-put ov 'after-string display-text)))))

(defun olive--message-result (text exit-code)
  "Show a concise minibuffer message for TEXT and EXIT-CODE."
  (let ((trimmed (string-trim text)))
    (message "%s"
             (cond
              ((not (zerop exit-code))
               (if (string-empty-p trimmed)
                   (format "olive exited %s" exit-code)
                 (replace-regexp-in-string "[\n\r\t ]+" " " trimmed)))
              ((string-empty-p trimmed) "")
              (t (replace-regexp-in-string "[\n\r\t ]+" " " trimmed))))))

(defun olive--insert-comment-result (buffer line-end text exit-code)
  "Insert TEXT as a // => result comment in BUFFER after LINE-END."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (save-excursion
        (goto-char line-end)
        (end-of-line)
        (if (eobp)
            (insert "\n")
          (forward-line 1))
        (while (and (not (eobp))
                    (looking-at-p "[[:space:]]*//[[:space:]]*=>"))
          (delete-region (line-beginning-position)
                         (min (point-max) (1+ (line-end-position)))))
        (let* ((trimmed (string-trim text))
               (single-line (replace-regexp-in-string "[\n\r\t ]+" " " trimmed)))
          (insert (format "// => %s%s\n"
                          (if (zerop exit-code) "" (format "<exit %s> " exit-code))
                          single-line)))))))

(defun olive--display-generated (generated)
  "Display GENERATED Odin in a separate buffer when non-nil."
  (when generated
    (let ((runner-buffer (olive--prepare-buffer olive-runner-buffer-name)))
      (with-current-buffer runner-buffer
        (let ((inhibit-read-only t))
          (insert generated)
          (when (fboundp 'odin-mode)
            (odin-mode))))
      (display-buffer runner-buffer))))

(defun olive--display-output (stdout stderr exit-code show-generated)
  "Display STDOUT and STDERR with EXIT-CODE.
When SHOW-GENERATED is non-nil, split generated Odin into a separate buffer when
possible."
  (let* ((visible-data (olive--visible-output stdout stderr show-generated))
         (generated (car visible-data))
         (visible (cdr visible-data))
         (result-buffer (olive--prepare-buffer olive-result-buffer-name)))
    (olive--display-generated generated)
    (with-current-buffer result-buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "$ olive exited %s\n\n" exit-code))
        (unless (string-empty-p visible)
          (insert visible)
          (unless (string-suffix-p "\n" visible)
            (insert "\n")))
        (goto-char (point-min))))
    (display-buffer result-buffer)
    (message "olive exited %s" exit-code)))

(defun olive--run (command package code &optional no-print show internal display bounds save)
  "Run olive COMMAND for PACKAGE and CODE."
  (setq olive--last-source-buffer (current-buffer))
  (let* ((source-buffer (current-buffer))
         (bounds (or bounds
                     (and (memq display '(inline comment))
                          (cons (line-beginning-position) (line-end-position)))))
         (default-directory (file-name-as-directory (expand-file-name olive-root)))
         (compiled (olive--compiled-command-or-error))
         (generated-file (and show (make-temp-file "olive-generated-" nil ".odin")))
         (stdout-buffer (generate-new-buffer " *olive-stdout*"))
         (stderr-buffer (generate-new-buffer " *olive-stderr*"))
         (args (olive--cli-args command package code no-print (and show (not generated-file)) internal save generated-file)))
    (make-process
     :name "olive"
     :buffer stdout-buffer
     :stderr stderr-buffer
     :command (cons compiled args)
     :noquery t
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (let ((exit-code (process-exit-status process))
               (stdout (with-current-buffer stdout-buffer
                         (buffer-substring-no-properties (point-min) (point-max))))
               (stderr (with-current-buffer stderr-buffer
                         (buffer-substring-no-properties (point-min) (point-max))))
               (generated-from-file (olive--read-generated-file generated-file)))
           (when (buffer-live-p stdout-buffer) (kill-buffer stdout-buffer))
           (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer))
           (pcase display
             ('inline
              (let* ((visible-data (olive--visible-output stdout stderr show))
                     (generated (or generated-from-file (car visible-data)))
                     (visible (cdr visible-data)))
                (olive--display-generated generated)
                (olive--show-inline-result source-buffer (car bounds) (cdr bounds) visible exit-code)
                (olive--message-result visible exit-code)))
             ('comment
              (let* ((visible-data (olive--visible-output stdout stderr show))
                     (generated (or generated-from-file (car visible-data)))
                     (visible (cdr visible-data)))
                (olive--display-generated generated)
                (olive--insert-comment-result source-buffer (cdr bounds) visible exit-code)
                (olive--message-result visible exit-code)))
             (_
              (if generated-from-file
                  (progn
                    (olive--display-generated generated-from-file)
                    (olive--display-output stdout stderr exit-code nil))
                (olive--display-output stdout stderr exit-code show))))))))))

(defun olive--run-store-command (args)
  "Run a olive store command with ARGS and display the result buffer."
  (let* ((default-directory (file-name-as-directory (expand-file-name olive-root)))
         (stdout-buffer (generate-new-buffer " *olive-store-stdout*"))
         (stderr-buffer (generate-new-buffer " *olive-store-stderr*")))
    (make-process
     :name "olive-store"
     :buffer stdout-buffer
     :stderr stderr-buffer
     :command (olive--process-command (cons "store" args))
     :noquery t
     :sentinel
     (lambda (process _event)
       (when (memq (process-status process) '(exit signal))
         (let ((exit-code (process-exit-status process))
               (stdout (with-current-buffer stdout-buffer
                         (buffer-substring-no-properties (point-min) (point-max))))
               (stderr (with-current-buffer stderr-buffer
                         (buffer-substring-no-properties (point-min) (point-max)))))
           (when (buffer-live-p stdout-buffer) (kill-buffer stdout-buffer))
           (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer))
           (olive--display-output stdout stderr exit-code nil)))))))

(defun olive-read-code ()
  "Read an Odin expression from the minibuffer, defaulting to symbol at point."
  (read-string "Odin expression: " (or (thing-at-point 'symbol t) "")))

(defun olive--strip-line-comment-prefix (text)
  "Strip Odin // comment prefixes from TEXT."
  (string-join
   (mapcar
    (lambda (line)
      (replace-regexp-in-string "\\`[[:space:]]*//[[:space:]]?" "" line))
    (split-string text "\n"))
   "\n"))

(defun olive--comment-line-p ()
  "Return non-nil when the current line starts with an Odin line comment."
  (save-excursion
    (beginning-of-line)
    (and (looking-at-p "[[:space:]]*//")
         (not (looking-at-p "[[:space:]]*//[[:space:]]*=>")))))

(defun olive--comment-block-bounds ()
  "Return bounds for the enclosing /* ... */ comment block around point."
  (let* ((cursor (point))
         (line-delimiter-p
          (save-excursion
            (beginning-of-line)
            (or (looking-at-p "[[:space:]]*/\\*[[:space:]]*$")
                (looking-at-p "[[:space:]]*\\*/[[:space:]]*$"))))
         (line-start (save-excursion (beginning-of-line) (point)))
         (line-end (save-excursion (end-of-line) (point)))
         (line-close-p
          (save-excursion
            (beginning-of-line)
            (looking-at-p "[[:space:]]*\\*/[[:space:]]*$")))
         (scan-end (if line-delimiter-p (line-end-position) cursor))
         (stack '())
         (line-close-bounds nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "/\\*\\|\\*/" scan-end t)
        (if (string= (match-string 0) "/*")
            (push (match-beginning 0) stack)
          (when stack
            (let ((closed (cons (pop stack) (match-end 0))))
              (when (and line-close-p
                         (>= (match-beginning 0) line-start)
                         (<= (match-end 0) line-end))
                (setq line-close-bounds closed)))))))
    (cond
     (line-close-p
      (or line-close-bounds
          (error "Point is not inside a /* ... */ comment block")))
     ((consp stack)
      (save-excursion
        (goto-char cursor)
        (unless (search-forward "*/" nil t)
          (error "Unterminated /* ... */ comment block around point"))
        (cons (car stack) (point))))
     (t
      (error "Point is not inside a /* ... */ comment block")))))

(defun olive--strip-comment-block-prefix (text)
  "Strip Odin /* ... */ comment markers from TEXT and normalize lines."
  (let* ((without-open
          (replace-regexp-in-string
           "\\`[[:space:]]*/\\*" "" text))
         (without-close
          (replace-regexp-in-string
           "\\*/[[:space:]]*\\'" "" without-open))
         (lines
          (mapcar
           (lambda (line)
             (replace-regexp-in-string "\\`[[:space:]]*\\*+[[:space:]]*" "" line))
           (split-string without-close "\n")))
         (without-results
          (string-join
           (seq-remove
            (lambda (line)
              (string-match-p "\\`[[:space:]]*//[[:space:]]*=>" line))
            lines)
           "\n")))
    (string-trim without-results)))

(defun olive--result-comment-line-p ()
  "Return non-nil when the current line is a olive // => result line."
  (save-excursion
    (beginning-of-line)
    (looking-at-p "[[:space:]]*//[[:space:]]*=>")))

(defun olive-comment-block-code ()
  "Return uncommented code from the enclosing /* ... */ comment block around point."
  (let* ((bounds (olive--comment-block-bounds))
         (text (buffer-substring-no-properties (car bounds) (cdr bounds)))
         (text-no-markers (olive--strip-comment-block-prefix text)))
    (string-trim (olive--strip-line-comment-prefix text-no-markers))))

(defun olive-current-line-code ()
  "Return code from the current line, stripping a leading // if present."
  (let ((line (string-trim
               (buffer-substring-no-properties
                (line-beginning-position)
                (line-end-position)))))
    (string-trim (olive--strip-line-comment-prefix line))))

(defun olive--call-bounds-before-point ()
  "Return bounds of the parenthesized call ending at or before point.
This is a lightweight Odin-aware helper for cases like:

  fmt.println(add(5,2)|)

where point is just after the inner call."
  (save-excursion
    (skip-chars-backward " \t\n")
    (when (and (> (point) (point-min))
               (eq (char-before) ?\)))
      (let ((end (point))
            (depth 0)
            (open nil))
        (while (and (> (point) (point-min))
                    (not open))
          (backward-char)
          (cond
           ((eq (char-after) ?\))
            (setq depth (1+ depth)))
           ((eq (char-after) ?\()
            (setq depth (1- depth))
            (when (zerop depth)
              (setq open (point))))))
        (when open
          (goto-char open)
          (skip-chars-backward " \t")
          (skip-chars-backward "A-Za-z0-9_\\.")
          (when (< (point) open)
            (cons (point) end)))))))

(defun olive--atom-bounds-before-point ()
  "Return bounds of the Odin atom ending at or before point."
  (save-excursion
    (skip-chars-backward " \t\n")
    (let ((end (point)))
      (skip-chars-backward "A-Za-z0-9_\\.$")
      (when (< (point) end)
        (cons (point) end)))))

(defun olive-current-line-call-or-atom-unit ()
  "Return current call/atom before point, falling back to current line."
  (if-let ((bounds (or (olive--call-bounds-before-point)
                       (olive--atom-bounds-before-point))))
      (cons (buffer-substring-no-properties (car bounds) (cdr bounds)) bounds)
    (cons (olive-current-line-code)
          (cons (line-beginning-position) (line-end-position)))))

(defun olive-current-line-bounds ()
  "Return bounds of the current line."
  (cons (line-beginning-position) (line-end-position)))

(defun olive-current-unit ()
  "Return (CODE . BOUNDS) for the current olive unit.
When point is inside a `/* ... */` block, the unit is the whole block.
Otherwise prefer the parenthesized call ending before point, falling back to the
atom before point, then the current line."
  (if-let ((bounds (ignore-errors (olive--comment-block-bounds))))
      (cons (olive-comment-block-code) bounds)
    (olive-current-line-call-or-atom-unit)))

;;;###autoload
(defun olive-run-expression (code)
  "Run Odin expression CODE in a generated runner for the current package."
  (interactive (list (olive-read-code)))
  (olive--run "run"
                 (olive-package-directory)
                 code
                 olive-default-no-print
                 olive-show-generated
                 nil
                 'buffer))

;;;###autoload
(defun olive-run-expression-save (code name)
  "Run Odin expression CODE and save successful stdout to store slot NAME."
  (interactive (list (olive-read-code)
                     (read-string "Save result as: ")))
  (olive--run "run"
                 (olive-package-directory)
                 code
                 olive-default-no-print
                 olive-show-generated
                 nil
                 'buffer
                 nil
                 name))

;;;###autoload
(defun olive-check-expression (code)
  "Check Odin expression CODE in a generated runner for the current package."
  (interactive (list (olive-read-code)))
  (olive--run "check"
                 (olive-package-directory)
                 code
                 olive-default-no-print
                 olive-show-generated
                 nil
                 'buffer))

;;;###autoload
(defun olive-store-save (name value)
  "Save VALUE to olive store slot NAME for the current package."
  (interactive (list (read-string "Store name: ")
                     (read-string "Value: ")))
  (olive--run-store-command (list "save" (olive-package-directory) name value)))

;;;###autoload
(defun olive-store-load (name)
  "Load olive store slot NAME for the current package into `*Olive*'."
  (interactive (list (read-string "Load store name: ")))
  (olive--run-store-command (list "load" (olive-package-directory) name)))

;;;###autoload
(defun olive-store-list ()
  "List olive store slots for the current package."
  (interactive)
  (olive--run-store-command (list "list" (olive-package-directory))))

;;;###autoload
(defun olive-store-remove (name)
  "Remove olive store slot NAME for the current package."
  (interactive (list (read-string "Remove store name: ")))
  (olive--run-store-command (list "rm" (olive-package-directory) name)))

;;;###autoload
(defun olive-store-path ()
  "Show the olive store path for the current package."
  (interactive)
  (olive--run-store-command (list "path" (olive-package-directory))))

;;;###autoload
(defun olive-run-line (&optional no-print)
  "Run the current olive unit and show the result inline.
If point is inside a scratch `/* ... */` block, run the whole block.
Otherwise run the current line. This is intended for scratch blocks such as:

  /*
  add(5,2)
  */

With prefix argument NO-PRINT, treat the line as statements."
  (interactive "P")
  (let ((unit (olive-current-unit)))
    (olive--run "run"
                   (olive-package-directory)
                   (car unit)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'inline
                   (cdr unit))))

;;;###autoload
(defun olive-run-whole-line (&optional no-print)
  "Run the whole current line and show the result inline.
This intentionally ignores point-sensitive call/atom selection."
  (interactive "P")
  (olive--run "run"
                 (olive-package-directory)
                 (olive-current-line-code)
                 (or no-print olive-default-no-print)
                 olive-show-generated
                 t
                 'inline
                 (olive-current-line-bounds)))

;;;###autoload
(defun olive-insert-line-result (&optional no-print)
  "Run the current olive unit and insert the result as a // => comment."
  (interactive "P")
  (let ((unit (olive-current-unit)))
    (olive--run "run"
                   (olive-package-directory)
                   (car unit)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'comment
                   (cdr unit))))

;;;###autoload
(defun olive-popup-line (&optional no-print)
  "Run the current olive unit and show output in the olive result buffer."
  (interactive "P")
  (let ((unit (olive-current-unit)))
    (olive--run "run"
                   (olive-package-directory)
                   (car unit)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'buffer
                   (cdr unit))))

;;;###autoload
(defun olive-run-line-save (&optional no-print)
  "Run the current olive unit and save successful stdout to a named store slot."
  (interactive "P")
  (let ((unit (olive-current-unit))
        (name (read-string "Save result as: ")))
    (olive--run "run"
                   (olive-package-directory)
                   (car unit)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'buffer
                   (cdr unit)
                   name)))

;;;###autoload
(defun olive-insert-comment-block-result (&optional no-print)
  "Run the current `/* ... */` comment block and insert a // => result comment."
  (interactive "P")
  (let ((bounds (olive--comment-block-bounds)))
    (olive--run "run"
                   (olive-package-directory)
                   (olive-comment-block-code)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'comment
                   bounds)))

;;;###autoload
(defun olive-check-line (&optional no-print)
  "Check the current line as Odin code inside the current package.
If the line starts with `//`, strip the comment prefix first."
  (interactive "P")
  (olive--run "check"
                 (olive-package-directory)
                 (olive-current-line-code)
                 (or no-print olive-default-no-print)
                 olive-show-generated
                 t
                 'buffer))

;;;###autoload
(defun olive-run-region (start end &optional no-print)
  "Run the selected Odin expression or statement region.
With prefix argument NO-PRINT, treat the region as statements."
  (interactive "r\nP")
  (olive--run "run"
                 (olive-package-directory)
                 (buffer-substring-no-properties start end)
                 (or no-print olive-default-no-print)
                 olive-show-generated
                 nil
                 'buffer))

;;;###autoload
(defun olive-check-region (start end &optional no-print)
  "Check the selected Odin expression or statement region.
With prefix argument NO-PRINT, treat the region as statements."
  (interactive "r\nP")
  (olive--run "check"
                 (olive-package-directory)
                 (buffer-substring-no-properties start end)
                 (or no-print olive-default-no-print)
                 olive-show-generated
                 nil
                 'buffer))

;;;###autoload
(defun olive-run-comment-block (&optional no-print)
  "Run uncommented code from the enclosing `/* ... */` comment block.
With prefix argument NO-PRINT, treat the code as statements.

This is the Odin analogue of keeping exploratory calls in a Clojure
`(comment ...)` form:

  /*
  target.answer()
  target.some_proc(1, 2)
  */"
  (interactive "P")
  (let ((bounds (olive--comment-block-bounds)))
    (olive--run "run"
                   (olive-package-directory)
                   (olive-comment-block-code)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'inline
                   bounds)))

;;;###autoload
(defun olive-check-comment-block (&optional no-print)
  "Check uncommented code from the enclosing `/* ... */` comment block.
With prefix argument NO-PRINT, treat the code as statements."
  (interactive "P")
  (let ((bounds (olive--comment-block-bounds)))
    (olive--run "check"
                   (olive-package-directory)
                   (olive-comment-block-code)
                   (or no-print olive-default-no-print)
                   olive-show-generated
                   t
                   'buffer
                   bounds)))

(defun olive--command-buffer (directory)
  "Return the command output buffer for DIRECTORY."
  (let ((buffer (get-buffer-create olive-result-buffer-name)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "$ cd %s\n" (abbreviate-file-name directory))))
      (special-mode)
      (setq-local truncate-lines nil)
      (setq-local word-wrap t)
      (visual-line-mode 1))
    buffer))

(defun olive--live-command-buffer (directory)
  "Return the live command output buffer for DIRECTORY."
  (let ((buffer (get-buffer-create olive-run-buffer-name)))
    (when-let ((process (get-buffer-process buffer)))
      (when (process-live-p process)
        (delete-process process)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "$ cd %s\n" (abbreviate-file-name directory))))
      (special-mode)
      (setq-local truncate-lines nil)
      (setq-local word-wrap t)
      (visual-line-mode 1))
    buffer))

(defun olive--live-process-filter (process chunk)
  "Insert live PROCESS output CHUNK."
  (when-let ((buffer (process-buffer process)))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert chunk))))))

(defun olive--reload-buffer-name (subcommand)
  "Return the live reload buffer name for SUBCOMMAND."
  (format "%s %s*"
          (string-remove-suffix "*" olive-reload-buffer-name)
          (if (string= subcommand "watch") "Watch" "Run")))

(defun olive--reload-process-name (subcommand)
  "Return the live reload process name for SUBCOMMAND."
  (format "olive-reload-%s" subcommand))

(defun olive--reload-buffer (directory subcommand)
  "Return the live reload output buffer for DIRECTORY and SUBCOMMAND."
  (let ((buffer (get-buffer-create (olive--reload-buffer-name subcommand))))
    (when-let ((process (get-buffer-process buffer)))
      (when (process-live-p process)
        (delete-process process)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (format "$ cd %s\n" (abbreviate-file-name directory))))
      (special-mode)
      (setq-local truncate-lines nil)
      (setq-local word-wrap t)
      (setq-local olive-reload-last-event nil)
      (visual-line-mode 1))
    buffer))

(defun olive--default-reload-target ()
  "Return a likely reload directory for the current buffer."
  (let* ((project (olive-project-directory))
         (package (olive-package-directory))
         (file (and buffer-file-name (expand-file-name buffer-file-name)))
         (candidates (delq nil
                           (list
                            (and file
                                 (string= (file-name-nondirectory file) "reload.odin")
                                 (file-name-directory file))
                            (and package
                                 (expand-file-name "reload" package))
                            (expand-file-name "reload" project)))))
    (or (seq-find
         (lambda (candidate)
           (file-exists-p (expand-file-name "reload.odin" candidate)))
         candidates)
        (expand-file-name "reload" project))))

(defun olive--read-reload-target ()
  "Read a reload directory."
  (let* ((default (olive--default-reload-target))
         (dir (file-name-directory default))
         (name (file-name-nondirectory default)))
    (read-file-name "Reload directory: " dir default t name)))

(defun olive--interactive-reload-target (&optional choose)
  "Return reload directory for an interactive command.
When CHOOSE is non-nil, prompt even if a default target exists."
  (if choose
      (olive--read-reload-target)
    (olive--default-reload-target)))

(defun olive--reload-event-value (event key)
  "Return KEY from parsed reload EVENT."
  (cond
   ((hash-table-p event) (gethash key event))
   ((listp event) (alist-get key event nil nil #'string=))))

(defun olive--format-reload-event (event)
  "Return a human-readable string for parsed reload EVENT."
  (let* ((kind (or (olive--reload-event-value event "kind") "unknown"))
         (generation (olive--reload-event-value event "generation"))
         (message (or (olive--reload-event-value event "message") ""))
         (base (if generation
                   (format "[reload] %s generation=%s" kind generation)
                 (format "[reload] %s" kind))))
    (if (string-empty-p message)
        base
      (format "%s: %s" base message))))

(defun olive--handle-reload-event-line (buffer line)
  "Handle one structured reload event LINE in BUFFER.
Return non-nil when LINE was a structured event."
  (when (string-prefix-p "OLIVE_RELOAD_EVENT\t" line)
    (let* ((payload (substring line (length "OLIVE_RELOAD_EVENT\t")))
           (event (ignore-errors
                    (json-parse-string payload :object-type 'hash-table)))
           (formatted (if event
                          (olive--format-reload-event event)
                        (format "[reload] malformed event: %s" payload))))
      (with-current-buffer buffer
        (setq-local olive-reload-last-event event)
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (insert formatted "\n")))
      (message "%s" formatted)
      t)))

(defun olive--reload-process-filter (process chunk)
  "Insert reload PROCESS output CHUNK, parsing structured event lines."
  (let* ((buffer (process-buffer process))
         (pending (concat (or (process-get process 'olive-reload-pending) "") chunk))
         (lines (split-string pending "\n"))
         (tail (if (string-suffix-p "\n" pending) "" (car (last lines))))
         (complete-lines (butlast lines)))
    (process-put process 'olive-reload-pending tail)
    (dolist (line complete-lines)
      (unless (and (process-get process 'olive-reload-json)
                   (olive--handle-reload-event-line buffer line))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (goto-char (point-max))
            (insert line "\n")))))))

(defun olive--flush-reload-process-tail (process)
  "Flush any pending partial output line for reload PROCESS."
  (let ((tail (process-get process 'olive-reload-pending)))
    (when (and tail (not (string-empty-p tail)))
      (process-put process 'olive-reload-pending "")
      (olive--reload-process-filter process "\n"))))

(defun olive--run-reload-command (directory target &optional json subcommand)
  "Run `olive SUBCOMMAND TARGET' in DIRECTORY.
SUBCOMMAND defaults to `run'. When JSON is non-nil, pass `--json' and parse
structured reload events."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (target (expand-file-name target))
         (subcommand (or subcommand "run"))
         (buffer (olive--reload-buffer directory subcommand))
         (stderr-buffer (generate-new-buffer " *olive-reload-stderr*"))
         (compiled (olive--compiled-command-or-error))
         (args (append (list subcommand target)
                       (when json (list "--json")))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "$ olive %s %s%s\n\n"
                        subcommand
                        target
                        (if json " --json" "")))))
    (let ((default-directory directory))
      (display-buffer buffer)
      (let ((process
             (make-process
              :name (olive--reload-process-name subcommand)
              :buffer buffer
              :stderr stderr-buffer
              :command (cons compiled args)
              :connection-type 'pipe
              :filter #'olive--reload-process-filter
              :noquery t
              :sentinel
              (lambda (process _event)
                (when (memq (process-status process) '(exit signal))
                  (olive--flush-reload-process-tail process)
                  (let ((exit-code (process-exit-status process))
                        (stderr (with-current-buffer stderr-buffer
                                  (buffer-substring-no-properties (point-min) (point-max)))))
                    (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer))
                    (with-current-buffer buffer
                      (let ((inhibit-read-only t))
                        (goto-char (point-max))
                        (unless (string-empty-p stderr)
                          (insert stderr)
                          (unless (string-suffix-p "\n" stderr) (insert "\n")))
                        (insert (format "\n$ olive %s exited %s\n" subcommand exit-code))))
                    (unless (zerop exit-code)
                      (display-buffer buffer))
                    (message "olive %s exited %s" subcommand exit-code)))))))
        (process-put process 'olive-reload-json json)
        process))))

(defun olive--stop-reload-command (subcommand)
  "Stop live reload SUBCOMMAND process if it is running."
  (let* ((buffer-name (olive--reload-buffer-name subcommand))
         (buffer (get-buffer buffer-name))
         (process (and buffer (get-buffer-process buffer))))
    (if (and process (process-live-p process))
        (progn
          (delete-process process)
          (message "stopped olive %s" subcommand))
      (message "no olive %s process running" subcommand))))

(defun olive--compact-command-output (stdout stderr)
  "Return compact one-line command output from STDOUT and STDERR."
  (let ((output (string-trim
                 (concat stdout
                         (unless (or (string-empty-p stdout)
                                     (string-empty-p stderr))
                           "\n")
                         stderr))))
    (replace-regexp-in-string "[\n\r\t ]+" " " output)))

(defun olive--run-olive-command (directory args label &optional on-success show-output-on-success)
  "Run compiled olive with ARGS in DIRECTORY.
Show `olive-result-buffer-name' only on failure. Run ON-SUCCESS on exit 0.
When SHOW-OUTPUT-ON-SUCCESS is non-nil, show command output in the minibuffer."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (buffer (olive--command-buffer directory))
         (stdout-buffer (generate-new-buffer " *olive-command-stdout*"))
         (stderr-buffer (generate-new-buffer " *olive-command-stderr*"))
         (compiled (olive--compiled-command-or-error)))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "$ olive %s\n\n" label))))
    (let ((default-directory directory))
      (make-process
       :name "olive-command"
       :buffer stdout-buffer
       :stderr stderr-buffer
       :command (cons compiled args)
       :connection-type 'pipe
       :noquery t
       :sentinel
       (lambda (process _event)
         (when (memq (process-status process) '(exit signal))
           (let ((exit-code (process-exit-status process))
                 (stdout (with-current-buffer stdout-buffer
                           (buffer-substring-no-properties (point-min) (point-max))))
                 (stderr (with-current-buffer stderr-buffer
                           (buffer-substring-no-properties (point-min) (point-max)))))
             (when (buffer-live-p stdout-buffer) (kill-buffer stdout-buffer))
             (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer))
             (with-current-buffer buffer
               (let ((inhibit-read-only t))
                 (goto-char (point-max))
                 (unless (string-empty-p stdout)
                   (insert stdout)
                   (unless (string-suffix-p "\n" stdout) (insert "\n")))
                 (unless (string-empty-p stderr)
                   (insert stderr)
                   (unless (string-suffix-p "\n" stderr) (insert "\n")))))
             (if (zerop exit-code)
                 (progn
                   (let ((compact-output (olive--compact-command-output stdout stderr)))
                     (message "%s"
                              (if (and show-output-on-success
                                       (not (string-empty-p compact-output)))
                                  compact-output
                                (format "olive %s: ok" label))))
                   (when on-success (funcall on-success)))
               (display-buffer buffer)
               (message "olive %s: failed" label)))))))))

(defun olive--command-in-project (args label &optional on-success show-output-on-success)
  "Run olive ARGS in the current project directory."
  (olive--run-olive-command (olive-project-directory) args label on-success show-output-on-success))

(defun olive--run-odin-command (directory args label &optional on-success show-output-on-success)
  "Run `odin' with ARGS in DIRECTORY.
Show `olive-result-buffer-name' only on failure. Run ON-SUCCESS on exit 0."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (buffer (olive--command-buffer directory))
         (stdout-buffer (generate-new-buffer " *olive-odin-stdout*"))
         (stderr-buffer (generate-new-buffer " *olive-odin-stderr*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "$ odin %s\n\n" label))))
    (let ((default-directory directory))
      (make-process
       :name "olive-odin-command"
       :buffer stdout-buffer
       :stderr stderr-buffer
       :command (cons "odin" args)
       :connection-type 'pipe
       :noquery t
       :sentinel
       (lambda (process _event)
         (when (memq (process-status process) '(exit signal))
           (let ((exit-code (process-exit-status process))
                 (stdout (with-current-buffer stdout-buffer
                           (buffer-substring-no-properties (point-min) (point-max))))
                 (stderr (with-current-buffer stderr-buffer
                           (buffer-substring-no-properties (point-min) (point-max)))))
             (when (buffer-live-p stdout-buffer) (kill-buffer stdout-buffer))
             (when (buffer-live-p stderr-buffer) (kill-buffer stderr-buffer))
             (with-current-buffer buffer
               (let ((inhibit-read-only t))
                 (goto-char (point-max))
                 (unless (string-empty-p stdout)
                   (insert stdout)
                   (unless (string-suffix-p "\n" stdout) (insert "\n")))
                 (unless (string-empty-p stderr)
                   (insert stderr)
                   (unless (string-suffix-p "\n" stderr) (insert "\n")))))
             (if (zerop exit-code)
                 (progn
                   (let ((compact-output (olive--compact-command-output stdout stderr)))
                     (message "%s"
                              (if (and show-output-on-success
                                       (not (string-empty-p compact-output)))
                                  compact-output
                                (format "odin %s: ok" label))))
                   (when on-success (funcall on-success)))
               (display-buffer buffer)
               (message "odin %s: failed" label)))))))))

(defun olive--run-live-odin-command (directory args label)
  "Run `odin' with ARGS in DIRECTORY, showing live output."
  (let* ((directory (file-name-as-directory (expand-file-name directory)))
         (buffer (olive--live-command-buffer directory))
         (command (mapconcat #'shell-quote-argument
                             (cons "odin" args)
                             " ")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (insert (format "$ odin %s\n\n" label))))
    (let ((default-directory directory))
      (display-buffer buffer)
      (make-process
       :name "olive-odin-run"
       :buffer buffer
       :command (list shell-file-name shell-command-switch
                      (concat "exec " command " 2>&1"))
       :connection-type 'pty
       :filter #'olive--live-process-filter
       :noquery t
       :sentinel
       (lambda (process _event)
         (when (memq (process-status process) '(exit signal))
           (let ((exit-code (process-exit-status process))
                 (buffer (process-buffer process)))
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (let ((inhibit-read-only t))
                   (goto-char (point-max))
                   (insert (format "\n$ odin run exited %s\n" exit-code)))))
             (message "odin run exited %s" exit-code))))))))

(defun olive--stop-live-run ()
  "Stop live `odin run' process if it is running."
  (let* ((buffer (get-buffer olive-run-buffer-name))
         (process (and buffer (get-buffer-process buffer))))
    (if (and process (process-live-p process))
        (progn
          (delete-process process)
          (message "stopped odin run"))
      (message "no odin run process running"))))

;;;###autoload
(defun olive-run-package ()
  "Run `odin run .' in the current Odin package directory."
  (interactive)
  (olive--run-live-odin-command (olive-package-directory) (list "run" ".") "run ."))

;;;###autoload
(defun olive-build-package ()
  "Run `odin build .' in the current Odin package directory."
  (interactive)
  (olive--run-odin-command
   (olive-package-directory)
   (list "build" ".")
   "build ."
   (when olive-test-after-build
     (lambda () (olive-test-package)))))

;;;###autoload
(defun olive-check-package ()
  "Run `odin check .' in the current Odin package directory."
  (interactive)
  (olive--run-odin-command (olive-package-directory) (list "check" ".") "check ."))

;;;###autoload
(defun olive-test-package ()
  "Run `odin test .' in the current Odin package directory."
  (interactive)
  (olive--run-odin-command
   (olive-package-directory)
   (append (list "test" ".") olive-test-args)
   (string-join (append (list "test" ".") olive-test-args) " ")
   nil
   t))

;;;###autoload
(defun olive-run-project ()
  "Run `odin run .' in the current Odin project directory."
  (interactive)
  (olive--run-live-odin-command (olive-project-directory) (list "run" ".") "run ."))

;;;###autoload
(defun olive-stop-run ()
  "Stop the live `odin run' process."
  (interactive)
  (olive--stop-live-run))

;;;###autoload
(defun olive-build-project ()
  "Run `odin build .' in the current Odin project directory."
  (interactive)
  (olive--run-odin-command (olive-project-directory) (list "build" ".") "build ."))

;;;###autoload
(defun olive-check-project ()
  "Run `odin check .' in the current Odin project directory."
  (interactive)
  (olive--run-odin-command (olive-project-directory) (list "check" ".") "check ."))

;;;###autoload
(defun olive-test-project ()
  "Run `odin test .' in the current Odin project directory."
  (interactive)
  (olive--run-odin-command
   (olive-project-directory)
   (append (list "test" ".") olive-test-args)
   (string-join (append (list "test" ".") olive-test-args) " ")
   nil
   t))

;;;###autoload
(defun olive-init (directory)
  "Create a generic Olive starter in DIRECTORY."
  (interactive "GReload starter directory: ")
  (olive--command-in-project
   (list "init" (expand-file-name directory))
   (format "init %s" directory)))

;;;###autoload
(defun olive-generate (target)
  "Generate hot-reload host/module wrappers from TARGET."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--command-in-project
   (list "generate" (expand-file-name target))
   (format "generate %s" target)
   nil
   t))

;;;###autoload
(defun olive-check (target)
  "Check hot-reload TARGET without building."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--command-in-project
   (list "check" (expand-file-name target))
   (format "check %s" target)
   nil
   t))

;;;###autoload
(defun olive-run (target)
  "Build and run hot-reload host from TARGET."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--run-reload-command (olive-project-directory) target))

;;;###autoload
(defun olive-run-json (target)
  "Build and run hot-reload host from TARGET with structured events."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--run-reload-command (olive-project-directory) target t))

;;;###autoload
(defun olive-build (target)
  "Build only the hot-reload module from TARGET."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--command-in-project
   (list "build" (expand-file-name target))
   (format "build %s" target)
   nil
   t))

;;;###autoload
(defun olive-watch (target)
  "Watch TARGET's reload paths and build the hot-reload module on changes."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--run-reload-command (olive-project-directory) target nil "watch"))

;;;###autoload
(defun olive-paths (target)
  "Show hot-reload generated paths for TARGET."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--command-in-project
   (list "paths" (expand-file-name target))
   (format "paths %s" target)
   nil
   t))

;;;###autoload
(defun olive-clean (target)
  "Remove hot-reload generated files and build outputs for TARGET."
  (interactive (list (olive--interactive-reload-target current-prefix-arg)))
  (olive--command-in-project
   (list "clean" (expand-file-name target))
   (format "clean %s" target)
   nil
   t))

;;;###autoload
(defun olive-stop-reload-run ()
  "Stop the live `olive run' reload process."
  (interactive)
  (olive--stop-reload-command "run"))

;;;###autoload
(defun olive-stop-watch ()
  "Stop the live `olive watch' process."
  (interactive)
  (olive--stop-reload-command "watch"))

;;;###autoload
(defun olive-toggle-test-after-build ()
  "Toggle running `odin test .' after successful package builds."
  (interactive)
  (setq olive-test-after-build (not olive-test-after-build))
  (message "olive-test-after-build: %s" olive-test-after-build))

;;;###autoload
(defun olive-run-proc (name args)
  "Run target proc NAME with raw Odin ARGS."
  (interactive
   (list (read-string "Proc: " (or (thing-at-point 'symbol t) ""))
         (read-string "Args: ")))
  (olive-run-expression (format "target.%s(%s)" name args)))

;;;###autoload
(defun olive-run-proc-no-args ()
  "Run the target proc at point with no arguments."
  (interactive)
  (let ((name (or (thing-at-point 'symbol t)
                  (read-string "Proc: "))))
    (olive-run-expression (format "target.%s()" name))))

;;;###autoload
(defun olive-toggle-show-generated ()
  "Toggle generated Odin display for olive commands."
  (interactive)
  (setq olive-show-generated (not olive-show-generated))
  (message "olive-show-generated: %s" olive-show-generated))

;;;###autoload
(defun olive-switch-to-result ()
  "Display the olive result buffer."
  (interactive)
  (pop-to-buffer olive-result-buffer-name))

;;;###autoload
(defun olive-switch-to-source ()
  "Return to the most recent olive source buffer."
  (interactive)
  (if (buffer-live-p olive--last-source-buffer)
      (pop-to-buffer olive--last-source-buffer)
    (message "No olive source buffer recorded.")))

(defun olive-setup-odin-mode-keys ()
  "Install olive keybindings in the current Odin buffer."
  (olive--enable-inline-result-clearing)
  (local-set-key (kbd "C-c C-e") #'olive-run-line)
  (local-set-key (kbd "C-c C-p") #'olive-popup-line)
  (local-set-key (kbd "C-c C-i") #'olive-insert-line-result)
  (local-set-key (kbd "C-c C-r") #'olive-run-region)
  (local-set-key (kbd "C-c C-c") #'olive-run-whole-line)
  (local-set-key (kbd "C-c C-x") #'olive-run-comment-block)
  (local-set-key (kbd "C-c C-k") #'olive-check-expression)
  (local-set-key (kbd "C-c C-a") #'olive-run-package)
  (local-set-key (kbd "C-c C-b") #'olive-build-package)
  (local-set-key (kbd "C-c C-v") #'olive-check-package)
  (local-set-key (kbd "C-c C-t") #'olive-test-package)
  (local-set-key (kbd "C-c C-q") #'olive-stop-run)
  (local-set-key (kbd "C-c C-s") #'olive-toggle-show-generated)
  (local-set-key (kbd "C-c C-l c") #'olive-check)
  (local-set-key (kbd "C-c C-l r") #'olive-run-json)
  (local-set-key (kbd "C-c C-l w") #'olive-watch)
  (local-set-key (kbd "C-c C-l b") #'olive-build)
  (local-set-key (kbd "C-c C-l k") #'olive-stop-reload-run)
  (local-set-key (kbd "C-c C-l K") #'olive-stop-watch)
  (local-set-key (kbd "C-c C-z") #'olive-switch-to-result))

(provide 'olive)

;;; olive.el ends here
