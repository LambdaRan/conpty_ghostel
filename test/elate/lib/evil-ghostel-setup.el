;;; evil-ghostel-setup.el --- Shared elate startup for the evil-ghostel matrix -*- lexical-binding: t; -*-

;; Loaded from a scenario's session.eval:
;;   (load ".../test/elate/lib/evil-ghostel-setup.el")
;; then the scenario (or the ELATE_GHOSTEL_SHELL env var) picks `ghostel-shell'.
;;
;; Sets up evil + ghostel + evil-ghostel from THIS checkout (self-locating, so
;; the scenarios keep working if the repo moves).  `evil' is resolved from the
;; usual local checkout or the Makefile's cache clone ($XDG_CACHE_HOME/evil).

;;; Code:

(let* ((here (file-name-directory (or load-file-name buffer-file-name)))
       (repo (expand-file-name "../../../" here))   ; test/elate/lib/ -> repo root
       ;; Resolve `evil' by ABSOLUTE path — elate sandboxes $HOME, so `~' points
       ;; at the fake home.  Primary: the sibling checkout next to this repo
       ;; (lib/evil beside lib/ghostel).  Fallbacks: ELATE_EVIL_DIR, the
       ;; Makefile's cache clone ($XDG_CACHE_HOME/evil).
       (evil (seq-find
              #'file-directory-p
              (delq nil
                    (list (getenv "ELATE_EVIL_DIR")
                          (expand-file-name "../evil" repo)
                          (and (getenv "XDG_CACHE_HOME")
                               (expand-file-name "evil" (getenv "XDG_CACHE_HOME"))))))))
  (unless evil
    (error "evil checkout not found (set ELATE_EVIL_DIR, or place it at %s)"
           (expand-file-name "../evil" repo)))
  (add-to-list 'load-path evil)
  (add-to-list 'load-path (expand-file-name "lisp" repo))
  (add-to-list 'load-path (expand-file-name "extensions/evil-ghostel" repo)))

(setq evil-want-keybinding nil
      evil-want-integration t
      evil-want-C-u-scroll t
      evil-want-Y-yank-to-eol t
      evil-undo-system 'undo-redo)
(require 'evil)
(evil-mode 1)
(require 'ghostel)
(require 'evil-ghostel)
(add-hook 'ghostel-mode-hook #'evil-ghostel-mode)

;; macOS `login(1)' would reset HOME/SHELL from the passwd DB, ignoring the
;; elate sandbox HOME; disable it so the sandbox stays isolated.
(setq ghostel-macos-login-shell nil
      ring-bell-function 'ignore)

;; Shell override via env var, so one setup file serves every matrix entry.
(when-let* ((sh (getenv "ELATE_GHOSTEL_SHELL")))
  (setq ghostel-shell sh))

(provide 'evil-ghostel-setup)
;;; evil-ghostel-setup.el ends here
