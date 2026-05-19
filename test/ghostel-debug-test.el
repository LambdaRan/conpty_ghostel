;;; ghostel-debug-test.el --- Tests for ghostel: debug -*- lexical-binding: t; -*-

;;; Commentary:

;; `ghostel-debug-keypress` rendering and `ghostel-debug-info` sections.

;;; Code:

(require 'ghostel-test-helpers)

(ert-deftest ghostel-test-debug-keypress-renders-capture ()
  "`ghostel--debug-kp-show' writes a paste-friendly report.
Drives the renderer with a synthetic state plist that mimics a captured
RET keystroke.  Asserts the report includes the event, every recorded
send, and the coalesce-buffer state."
  (let* ((target (generate-new-buffer " *ghostel-test-debug-kp*"))
         (state (list :buffer target
                      :event ?\C-m
                      :keys [13]
                      :command 'ghostel--send-event
                      :binding 'ghostel--send-event
                      :calls (list (cons :flush-output "\r")
                                   (cons :send-string "ls")))))
    (unwind-protect
        (progn
          (ghostel--debug-kp-show state)
          (with-current-buffer "*ghostel-debug-keypress*"
            (let ((content (buffer-string)))
              (should (string-match-p "^=== ghostel-debug-keypress ===" content))
              (should (string-match-p "last-input-event:" content))
              (should (string-match-p "Sends during this command" content))
              ;; Calls were collected newest-first; renderer reverses them.
              (should (string-match-p "1\\. send-string: \"ls\"" content))
              (should (string-match-p "hex: 6c 73" content))
              (should (string-match-p "2\\. flush-output:" content))
              (should (string-match-p "hex: 0d" content))
              (should (string-match-p "Coalesce buffer" content)))))
      (kill-buffer target)
      (when (get-buffer "*ghostel-debug-keypress*")
        (kill-buffer "*ghostel-debug-keypress*")))))

(ert-deftest ghostel-test-debug-info-environment-section ()
  "`ghostel-debug-info' renders the Environment section.
The section shows the spawn env ghostel hands the shell (TERM,
COLORTERM, INSIDE_EMACS, …) plus pass-through LANG/LC_*.  In a
non-ghostel buffer (no `default-directory' override), the local-spawn
branch fires and emits the full TERM/COLORTERM line set."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t)
        (ghostel--terminfo-warned t))
    (unwind-protect
        (save-window-excursion
          (with-temp-buffer
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (let ((content (buffer-string)))
                (should (string-match-p "--- Environment ---" content))
                (should (string-match-p "Spawn env (set by ghostel, local spawn)"
                                        content))
                (should (string-match-p "INSIDE_EMACS=ghostel" content))
                (should (string-match-p "^  TERM=" content))
                (should (string-match-p "COLORTERM=" content))
                (should (string-match-p "Pass-through" content))
                (should (string-match-p "LANG=" content))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(ert-deftest ghostel-test-debug-info-environment-section-remote-labeling ()
  "Remote ghostel buffer → Environment section hides local-spawn vars.
For a remote ghostel buffer the on-remote `/bin/sh -c' preamble owns
TERM/TERMINFO/TERM_PROGRAM/COLORTERM (issue #224 fix), so showing the
local `(ghostel--terminal-env)' as if it were the spawn env is
misleading.  Verify the new label fires and TERM/COLORTERM lines are
suppressed; INSIDE_EMACS still shows because it's pushed regardless."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t))
    (unwind-protect
        (save-window-excursion
          (ghostel-test--with-compile-buffer buf
            (setq-local default-directory "/ssh:host.example.com:/tmp/")
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (let ((content (buffer-string)))
                (should (string-match-p
                         "Spawn env (set by ghostel, remote spawn)"
                         content))
                (should (string-match-p "INSIDE_EMACS=ghostel" content))
                ;; Local-only entries must not appear under "Spawn env".
                ;; The Pass-through section still shows LANG.
                (should-not (string-match-p "^  TERM=" content))
                (should-not (string-match-p "^  TERMINFO=" content))
                (should-not (string-match-p "^  COLORTERM=" content))
                ;; The clarifying note pointing the user to the wrapper.
                (should (string-match-p
                         "set by the on-remote /bin/sh -c preamble"
                         content))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(ert-deftest ghostel-test-debug-info-tramp-section-on-remote ()
  "`ghostel-debug-info' adds a TRAMP section for remote ghostel buffers.
TRAMP knobs that load-bear in `make-process' dispatch (and that
silently misbehave for #224-class bugs) belong in the standard report."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t))
    (unwind-protect
        (save-window-excursion
          (ghostel-test--with-compile-buffer buf
            (setq-local default-directory "/ssh:host.example.com:/tmp/")
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (let ((content (buffer-string)))
                (should (string-match-p "^--- TRAMP ---" content))
                (should (string-match-p "tramp-version:" content))
                (should (string-match-p "tramp-terminal-type:" content))
                (should (string-match-p "direct-async (global):" content))
                (should (string-match-p "direct-async (effective):" content))
                (should (string-match-p "Would dispatch direct-async:" content))
                (should (string-match-p "Multi-hop length:" content))
                (should (string-match-p
                         "TERM (connection shell):" content))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(ert-deftest ghostel-test-debug-info-tramp-section-absent-locally ()
  "Local ghostel buffer → no TRAMP section.
Avoids cluttering local-only reports with TRAMP irrelevancies."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t))
    (unwind-protect
        (save-window-excursion
          (ghostel-test--with-compile-buffer buf
            (setq-local default-directory "/tmp/")
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (should-not (string-match-p "^--- TRAMP ---"
                                          (buffer-string))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(ert-deftest ghostel-test-debug-info-spawn-capture-absent ()
  "`ghostel-debug-info' notes the missing capture in plain ghostel buffers.
The hint must point users to `ghostel-debug-ghostel' so they know how
to capture spawn-time diagnostics on the next reproduction."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t))
    (unwind-protect
        (save-window-excursion
          (ghostel-test--with-compile-buffer buf
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (let ((content (buffer-string)))
                (should (string-match-p "^--- Spawn capture ---" content))
                (should (string-match-p "no capture" content))
                (should (string-match-p "ghostel-debug-ghostel" content))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(ert-deftest ghostel-test-debug-info-spawn-capture-renders ()
  "`ghostel-debug-info' renders the spawn capture when present.
Drives the renderer with a synthesized capture plist that mimics what
`ghostel-debug-ghostel' would have stashed for a remote spawn.  Asserts
the wrapper script, geometry, env delta, and PTY-output / send-key
sections all materialize."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t))
    (unwind-protect
        (save-window-excursion
          (ghostel-test--with-compile-buffer buf
            (let* ((t-sp (current-time))
                   (t0 (time-add t-sp 0.123))   ; +123ms elisp prep
                   (t1 (time-add t0 0.010))     ; +10ms first PTY byte
                   (t2 (time-add t0 0.500))
                   (t3 (time-add t0 0.700)))
              (setq-local ghostel-debug--spawn-capture
                          (list :time t0
                                :start-process-time t-sp
                                :default-directory "/ssh:host.example.com:/tmp/"
                                :remote-p t
                                :program "/bin/bash"
                                :program-args nil
                                :height 24 :width 80
                                :stty-flags ghostel--default-stty
                                :extra-env nil
                                :process-environment
                                '("INSIDE_EMACS=ghostel"
                                  "TERM=xterm-ghostty"
                                  "PATH=/usr/bin")
                                :command
                                '("/bin/sh" "-c"
                                  "TERM=xterm-256color; if infocmp xterm-ghostty >/dev/null 2>&1; then TERM=xterm-ghostty; fi; export TERM; exec /bin/bash")
                                ;; Mimic TRAMP's legacy-async dispatch:
                                ;; the local bridge process differs from
                                ;; the wrapper ghostel built.
                                :executed-command '("/bin/sh" "-i")
                                :filter-events
                                (list (cons t1 "\e]0;hostname\007$ "))
                                :filter-cap 16384
                                :filter-bytes (length "\e]0;hostname\007$ ")
                                :filter-truncated nil
                                :send-keys
                                (list (cons t2 "l")
                                      (cons t3 "s"))
                                :send-cap 64
                                :send-truncated nil)))
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (let ((content (buffer-string)))
                (should (string-match-p "^--- Spawn capture ---" content))
                (should (string-match-p "Captured at:" content))
                (should (string-match-p "Remote-p:            yes" content))
                (should (string-match-p "Program:             /bin/bash"
                                        content))
                (should (string-match-p "Geometry:            80x24" content))
                ;; The wrapper script — load-bearing for #224.
                (should (string-match-p "Wrapper command sent" content))
                (should (string-match-p "infocmp xterm-ghostty" content))
                ;; The legacy-async divergence section — :executed-command
                ;; differs from :command, so the renderer must surface it.
                (should (string-match-p
                         "Local process command (`process-command'):"
                         content))
                (should (string-match-p "    -i" content))
                (should (string-match-p
                         "TRAMP rewrote the command for legacy-async"
                         content))
                ;; Env delta header.
                (should (string-match-p "process-environment at spawn"
                                        content))
                ;; Phase timings: T0 baseline, +123ms spawn-pty entry,
                ;; +133ms first PTY byte (123 + 10 from t-sp).
                (should (string-match-p "^Phase timings:" content))
                (should (string-match-p
                         "T0 +ghostel--start-process entered" content))
                (should (string-match-p
                         "\\+123ms +ghostel--spawn-pty entered" content))
                (should (string-match-p
                         "\\+133ms +first PTY byte received" content))
                ;; Unified RECV/SEND timeline.
                (should (string-match-p "^Timeline (RECV cap=" content))
                (should (string-match-p "RECV  \"" content))
                (should (string-match-p "SEND  \"l\"" content))
                (should (string-match-p "SEND  \"s\"" content))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(ert-deftest ghostel-test-debug-capture-filter-bounded ()
  "`ghostel-debug--capture-filter' records timestamped events and caps total bytes.
Each call appends a (TS . CHUNK) event up to :filter-cap total bytes.
Once the cap is hit, :filter-truncated is set and further chunks are
dropped (so steady-state shell output doesn't accumulate unboundedly)."
  (ghostel-test--with-compile-buffer buf
    (setq-local ghostel-debug--spawn-capture
                (list :filter-events nil
                      :filter-cap 16
                      :filter-bytes 0
                      :filter-truncated nil))
    (let ((proc (make-pipe-process :name "ghostel-test-capture"
                                   :buffer buf :noquery t)))
      (unwind-protect
          (cl-flet ((events-bytes ()
                      (mapconcat #'cdr
                                 (plist-get ghostel-debug--spawn-capture
                                            :filter-events)
                                 "")))
            (ghostel-debug--capture-filter proc "0123456789")
            (should (= 1 (length (plist-get ghostel-debug--spawn-capture
                                            :filter-events))))
            (should (equal (events-bytes) "0123456789"))
            (should (= 10 (plist-get ghostel-debug--spawn-capture
                                     :filter-bytes)))
            (should-not (plist-get ghostel-debug--spawn-capture
                                   :filter-truncated))
            ;; This chunk overflows the 16-byte cap (10 + 10 = 20):
            ;; the first 6 bytes fit, the rest is dropped and the
            ;; truncated flag flips on.
            (ghostel-debug--capture-filter proc "ABCDEFGHIJ")
            (should (= 2 (length (plist-get ghostel-debug--spawn-capture
                                            :filter-events))))
            (should (equal (events-bytes) "0123456789ABCDEF"))
            (should (= 16 (plist-get ghostel-debug--spawn-capture
                                     :filter-bytes)))
            (should (plist-get ghostel-debug--spawn-capture
                               :filter-truncated))
            ;; Further chunks no-op against the cap — no new event,
            ;; total bytes unchanged.
            (ghostel-debug--capture-filter proc "more")
            (should (= 2 (length (plist-get ghostel-debug--spawn-capture
                                            :filter-events))))
            (should (= 16 (plist-get ghostel-debug--spawn-capture
                                     :filter-bytes))))
        (delete-process proc)))))

(ert-deftest ghostel-test-debug-capture-send-bounded ()
  "`ghostel-debug--capture-send-string' caps :send-keys and flags truncation."
  (ghostel-test--with-compile-buffer buf
    (setq-local ghostel-debug--spawn-capture
                (list :send-keys nil
                      :send-cap 2
                      :send-truncated nil))
    (ghostel-debug--capture-send-string "a")
    (ghostel-debug--capture-send-string "b")
    (should (= 2 (length (plist-get ghostel-debug--spawn-capture
                                    :send-keys))))
    (should-not (plist-get ghostel-debug--spawn-capture :send-truncated))
    (ghostel-debug--capture-send-string "c")
    (should (= 2 (length (plist-get ghostel-debug--spawn-capture
                                    :send-keys))))
    (should (plist-get ghostel-debug--spawn-capture :send-truncated))))

(ert-deftest ghostel-test-debug-info-phase-timings-without-start-time ()
  "Phase timings still render when `:start-process-time' is absent.
Spawn-captures created via direct `ghostel--spawn-pty' calls (not
through `ghostel--start-process') have no elisp-prep baseline; the
section must degrade gracefully and still report the spawn-pty/first-
byte delta."
  (let ((display-buffer-overriding-action '(display-buffer-no-window))
        (inhibit-message t))
    (unwind-protect
        (save-window-excursion
          (ghostel-test--with-compile-buffer buf
            (let* ((t0 (current-time))
                   (t1 (time-add t0 0.042)))
              (setq-local ghostel-debug--spawn-capture
                          (list :time t0
                                :start-process-time nil
                                :default-directory "/tmp/"
                                :remote-p nil
                                :program "/bin/sh"
                                :program-args nil
                                :height 24 :width 80
                                :stty-flags ghostel--default-stty
                                :extra-env nil
                                :process-environment process-environment
                                :command '("/bin/sh" "-c" "exec /bin/sh")
                                ;; Local spawn — no TRAMP rewriting,
                                ;; so the executed cmd matches.
                                :executed-command
                                '("/bin/sh" "-c" "exec /bin/sh")
                                :filter-events (list (cons t1 "$ "))
                                :filter-cap 16384
                                :filter-bytes 2
                                :filter-truncated nil
                                :send-keys nil
                                :send-cap 64
                                :send-truncated nil)))
            (ghostel-debug-info)
            (with-current-buffer "*ghostel-debug*"
              (let ((content (buffer-string)))
                (should (string-match-p "^Phase timings:" content))
                ;; No T0 baseline line when start-process-time is nil.
                (should-not (string-match-p
                             "ghostel--start-process entered" content))
                ;; spawn-pty is the baseline (T0); first byte is +42ms.
                (should (string-match-p
                         "T0 +ghostel--spawn-pty entered" content))
                (should (string-match-p
                         "\\+42ms +first PTY byte received" content))
                ;; :command and :executed-command match (local spawn,
                ;; no TRAMP rewriting), so the divergence section must
                ;; be suppressed.
                (should-not (string-match-p
                             "Local process command" content))
                (should-not (string-match-p
                             "TRAMP rewrote" content))))))
      (when (get-buffer "*ghostel-debug*")
        (kill-buffer "*ghostel-debug*")))))

(provide 'ghostel-debug-test)
;;; ghostel-debug-test.el ends here
