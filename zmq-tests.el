;;; zmq-tests.el --- Tests for emacs-zmq-*- lexical-binding: t -*-

;; Copyright (C) 2018 Nathaniel Nicandro

;; Author: Nathaniel Nicandro <nathanielnicandro@gmail.com>
;; Created: 27 Sep 2018
;; Version: 0.0.1
;; Keywords:
;; X-URL: https://github.com/nathan/zmq-tests

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2, or (at
;; your option) any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Commentary:

;;; Code:

(require 'cl-lib)
(require 'ert)
(require 'zmq)

(defun zmq-create-bound-pair (ctx type1 type2 &optional interface)
  (setq interface (or interface "tcp://127.0.0.1"))
  (let ((s1 (zmq-socket ctx type1))
        (s2 (zmq-socket ctx type2)))
    (zmq-set-option s1 zmq-LINGER 0)
    (zmq-set-option s2 zmq-LINGER 0)
    (let ((port (zmq-bind-to-random-port s1 interface)))
      (zmq-connect s2 (format "%s:%d" interface port)))
    (list s1 s2)))

(defmacro zmq-test-with-bound-pair (ctx spec &optional interface &rest body)
  (declare (debug (symbolp ((symbolp symbolp) (symbolp symbolp))
                           &optional [&or stringp form] &rest form)))
  (unless (stringp interface)
    (when interface
      (setq body (cons interface body)
            interface nil)))
  (cl-destructuring-bind ((s1 type1) (s2 type2)) spec
    `(cl-destructuring-bind (,s1 ,s2)
         (zmq-create-bound-pair ,ctx ,type1 ,type2 ,interface)
       (unwind-protect
           (progn ,@body)
         (zmq-unbind ,s1 (zmq-socket-get ,s1 zmq-LAST-ENDPOINT))
         (zmq-disconnect ,s2 (zmq-socket-get ,s2 zmq-LAST-ENDPOINT))))))

(ert-deftest zmq-utility ()
  (ert-info ("`zmq-version'")
    (let ((version (zmq-version)))
      (should (version<= "4.0.0" version))))
  (ert-info ("`zmq-has'")
    (should (or (eq (zmq-has "draft") t)
                (eq (zmq-has "draft") nil))))
  (let* ((ctx (zmq-context))
         (sock (zmq-socket ctx zmq-PUB)))
    (ert-info ("Convenience functions")
      (ert-info ("`zmq-bind-to-random-port'")
        (should-error
         (zmq-bind-to-random-port sock "tcp:*")
         :type 'zmq-EINVAL)
        (should-error
         (zmq-bind-to-random-port sock "rand://")
         :type 'zmq-EPROTONOSUPPORT)))))

(ert-deftest zmq-encryption ()
  (ert-info ("CURVE mechanism")
    (when (zmq-has "curve")
      (cl-destructuring-bind (public-key . secret-key)
          (zmq-curve-keypair)
        (should (string= (zmq-z85-encode (zmq-z85-decode public-key)) public-key))
        (should (string= public-key (zmq-curve-public secret-key)))))))

(ert-deftest zmq-contexts ()
  (let (ctx)
    (ert-info ("Creating contexts")
      (setq ctx (zmq-context)))
    (ert-info ("Setting/getting context options")
      (zmq-set-option ctx zmq-MAX-MSGSZ 100)
      (should (= (zmq-get-option ctx zmq-MAX-MSGSZ) 100))
      (zmq-context-set ctx zmq-MAX-MSGSZ 200)
      (should (= (zmq-context-get ctx zmq-MAX-MSGSZ) 200))
      ;; BOOL options
      (zmq-context-set ctx zmq-BLOCKY nil)
      (should-not (zmq-context-get ctx zmq-BLOCKY))
      (zmq-context-set ctx zmq-BLOCKY t)
      (should (eq (zmq-context-get ctx zmq-BLOCKY) t))
      (should-error (zmq-context-get ctx "foo")
                    :type 'wrong-type-argument)
      (should-error (zmq-context-get "bar" zmq-MAX-MSGSZ)
                    :type 'wrong-type-argument))))

(ert-deftest zmq-messages ()
  (ert-info ("Message initialization")
    (let ((msg (zmq-message)))
      (ert-info ("Empty constructor")
        (should (= (zmq-message-size msg) 0))
        (should (equal (zmq-message-data msg) "")))
      (ert-info ("Constructor with contents")
        (setq msg (zmq-message "aa"))
        (should (equal (zmq-message-data msg) "aa"))
        (ert-info ("Integer vectors")
          (setq msg (zmq-message [10 10]))
          (should (equal (zmq-message-data msg) "\n\n"))))
      (ert-info ("Constructor with invalid argument")
        (should-error (zmq-message t)
                      :type 'wrong-type-argument))
      (ert-info ("Test message initialization")
        (ert-info ("Strings")
          (setq msg (zmq-message "msg1"))
          (should (= (zmq-message-size msg) 4))
          (should (equal (zmq-message-data msg) "msg1")))
        (ert-info ("Integer vectors")
          (setq msg (zmq-message [10 0 10]))
          (should (equal (zmq-message-data msg) "\n\0\n"))
          (should-error (zmq-message [256 0 10])
                        :type 'args-out-of-range)))))
  (ert-info ("Moving messages")
    (let ((msg1 (zmq-message "msg1"))
          (msg2 (zmq-message "msg2")))
      (should (equal (zmq-message-data msg1) "msg1"))
      (should (equal (zmq-message-data msg2) "msg2"))
      (zmq-message-move msg1 msg2)
      (should (equal (zmq-message-data msg2) "msg1"))
      (should (equal (zmq-message-data msg1) ""))))
  (ert-info ("Copying messages")
    (let ((msg1 (zmq-message "msg1")) msg2)
      (should (equal (zmq-message-data msg1) "msg1"))
      (setq msg2 (zmq-message-copy msg1))
      (should (zmq-message-p msg2))
      (should (equal (zmq-message-data msg2) "msg1"))
      (should (equal (zmq-message-data msg1) "msg1"))))
  (ert-info ("Message properties")
    (let ((msg (zmq-message)))
      (zmq-message-set-routing-id msg 10)
      (should (= (zmq-message-routing-id msg) 10))
      (should-not (zmq-message-get msg zmq-MORE))))
  (ert-info ("Sending/receiving messages")
    (let ((ctx (zmq-context))
          (msg (zmq-message)))
      (zmq-test-with-bound-pair
       ctx ((p zmq-REP) (s zmq-REQ))
       (ert-info ("Metadata of received messages")
         (zmq-send s "hello")
         (zmq-message-recv msg p)
         (should (equal (zmq-message-property msg :socket-type) "REQ")))
       (ert-info ("Multipart messages")
         (let ((parts '("foo" "bar")))
           (while (cdr parts)
             (zmq-message-send (zmq-message (car parts)) p zmq-SNDMORE)
             (setq parts (cdr parts)))
           (zmq-message-send (zmq-message (car parts)) p))
         (setq msg (zmq-message))
         (zmq-message-recv msg s)
         (should (equal (zmq-message-data msg) "foo"))
         (should (zmq-message-more-p msg))
         (setq msg (zmq-message))
         (zmq-message-recv msg s)
         (should (equal (zmq-message-data msg) "bar"))
         (should-not (zmq-message-more-p msg)))))))

(ert-deftest zmq-send-unicode ()
  (ert-info ("Unicode messages")
    (let* ((contents "[â, â†] = 1")
           (msg (zmq-message contents)))
      ;; zmq only deals in bytes
      (should-not (= (zmq-message-size msg) (length contents)))
      (should (= (zmq-message-size msg) (string-bytes contents)))
      ;; but on conversion to an Emacs string, if the data represents a unicode
      ;; strings its converted to one.
      (should (equal (zmq-message-data msg) contents)))
    (ert-info ("Sending unicode messages")
      (let* ((ctx (zmq-context)))
        (zmq-test-with-bound-pair
         ctx ((s1 zmq-PAIR) (s2 zmq-PAIR))
         (let ((u "çπ§")
               (s nil))
           (zmq-send s1 u)
           (setq s (zmq-recv s2))
           (should (equal s u))
           (zmq-send-encoded s1 u 'utf-16)
           (setq s (zmq-recv-decoded s2 'utf-16))
           (should (equal s u))))))))

(ert-deftest zmq-sockets ()
  (let* ((ctx (zmq-context))
         (endpoint "tcp://127.0.0.1:5345")
         (s (zmq-socket ctx zmq-PUB)))
    (ert-info ("Connecting sockets")
      (should-error
       (zmq-bind s "photon://a")
       :type 'zmq-EPROTONOSUPPORT)
      (should-error
       (zmq-connect s "photon://a")
       :type 'zmq-EPROTONOSUPPORT)
      (should-error
       (zmq-bind s "tcp://")
       :type 'zmq-EINVAL)
      (zmq-bind s endpoint)
      (unwind-protect
          (should (equal (zmq-socket-get s zmq-LAST-ENDPOINT) endpoint))
        (zmq-unbind s endpoint))
      (zmq-connect s endpoint)
      (unwind-protect
          (should (equal (zmq-socket-get s zmq-LAST-ENDPOINT) endpoint))
        (zmq-disconnect s endpoint)))
    (ert-info ("Socket options")
      (let ((sock (zmq-socket ctx zmq-PULL)))
        (ert-info ("Integer options")
          (zmq-set-option sock zmq-CONNECT-TIMEOUT 100)
          (should (= (zmq-get-option sock zmq-CONNECT-TIMEOUT) 100))
          (zmq-set-option sock zmq-AFFINITY 4)
          (should (= (zmq-get-option sock zmq-AFFINITY) 4))
          (zmq-set-option sock zmq-MAXMSGSIZE 256)
          (should (= (zmq-get-option sock zmq-MAXMSGSIZE) 256)))
        (ert-info ("Integer options with boolean types")
          (zmq-set-option sock zmq-CONFLATE t)
          (should (eq (zmq-get-option sock zmq-CONFLATE) t))
          ;; Follow the Emacs convention that anything non-nil is considered a
          ;; true value
          (zmq-set-option sock zmq-IMMEDIATE 0)
          (should (eq (zmq-get-option sock zmq-IMMEDIATE) t)))
        (ert-info ("String options")
          (zmq-set-option sock zmq-PLAIN-PASSWORD "password")
          (should (equal (zmq-get-option sock zmq-PLAIN-PASSWORD)
                         "password"))
          ;; TODO: This should probably fail to enforce calling the
          ;; encoding/decoding functions explicitly.
          (zmq-set-option sock zmq-PLAIN-PASSWORD "paßword")
          (should (equal (zmq-get-option sock zmq-PLAIN-PASSWORD)
                         "paßword")))
        (ert-info ("Binary options")
          (let ((identity "identity\0\0"))
            (zmq-set-option sock zmq-ROUTING-ID identity)
            (should (equal (zmq-get-option sock zmq-ROUTING-ID) identity))))
        (ert-info ("CURVE options")
          (when (zmq-has "curve")
            (cl-destructuring-bind (pub . priv)
                (zmq-curve-keypair)
              (zmq-set-option sock zmq-CURVE-PUBLICKEY pub)
              (zmq-set-option sock zmq-CURVE-SERVERKEY priv)
              ;; Always returns the string representation
              (should (equal (zmq-get-option sock zmq-CURVE-PUBLICKEY)
                             pub))
              (should (equal (zmq-get-option sock zmq-CURVE-SERVERKEY)
                             priv)))))
        (let ((sock (zmq-socket ctx zmq-SUB)))
          (ert-info ("Unicode options")
            (let ((topic "tést"))
              (zmq-socket-set-encoded sock zmq-ROUTING-ID topic 'utf-16)
              (should (equal (zmq-socket-get-decoded sock zmq-ROUTING-ID 'utf-16)
                             topic))
              (zmq-socket-set-encoded sock zmq-SUBSCRIBE topic 'utf-16))))))))

(ert-deftest zmq-polling ()
  (let ((ctx (zmq-current-context)))
    ;; https://github.com/zeromq/pyzmq/blob/master/examples/poll/pubsub.py
    (ert-info ("`zmq-poller'")
      (zmq-test-with-bound-pair
       ctx ((p zmq-PUB) (s zmq-SUB))
       (let ((poller (zmq-poller)))
         (let ((events nil))
           ;; Allow sockets to connect
           (sleep-for 0.5)

           ;; Subscribe to all incoming messages
           (zmq-socket-set s zmq-SUBSCRIBE "")

           (zmq-poller-add poller p (list zmq-POLLIN zmq-POLLOUT))
           (zmq-poller-add poller s (list zmq-POLLIN zmq-POLLOUT))

           (setq events (zmq-poller-wait-all poller 10 100))
           (should (member zmq-POLLOUT (zmq-assoc p events)))
           (should-not (alist-get s events))

           (zmq-send p "msg1")
           (setq events (zmq-poller-wait-all poller 10 100))
           (should (member zmq-POLLOUT (zmq-assoc p events)))

           (sleep-for 0.1)

           (setq events (zmq-poller-wait-all poller 10 1000))
           (should (member zmq-POLLIN (zmq-assoc s events)))

           (should (equal (zmq-recv s) "msg1"))
           (setq events (zmq-poller-wait-all poller 10 100))
           (should-not (zmq-assoc s events))))))))

(ert-deftest zmq-subprocess ()
  (ert-info ("Validating sexp")
    (let (proc foo)
      (unwind-protect
          (progn
            (should-error (setq proc (zmq-start-process (list 1 2 3))))
            (ert-info ("Only functions with 0 or 1 arguments")
              (should-error (setq proc (zmq-start-process
                                        (lambda (a b)))))))
        (when proc
          (delete-process proc)))))
  (ert-info ("Subprocess wraps function with context")
    (let* ((body (quote ((if zmq-current-context
                             (prin1 (cons 'test-result "context"))
                           (prin1 (cons 'test-result "no context")))
                         (zmq-flush 'stdout))))
           (process)
           (filter-called nil))
      (setq
       process (zmq-start-process
                `(lambda () ,@body)
                :filter (lambda (event)
                          (setq filter-called t)
                          (should (equal (cdr event) "no context")))))
      (with-timeout (0.4 nil)
        (while (not filter-called)
          (sleep-for 0.01)))
      (should filter-called)
      (delete-process process)
      (setq filter-called nil)
      (setq
       process (zmq-start-process
                `(lambda (ctx) ,@body)
                :filter (lambda (event)
                          (setq filter-called t)
                          (should (equal (cdr event) "context")))))
      (with-timeout (0.4 nil)
        (while (not filter-called)
          (sleep-for 0.01)))
      (should filter-called)
      (delete-process process)))
  (let ((process (zmq-start-process (lambda () (sleep-for 1000))))
        sexp)
    (unwind-protect
        (ert-info ("Subprocess output")
          (ert-info ("Reading sexp from process output")
            (ert-info ("Reading a single sexp")
              (with-temp-buffer
                (setq sexp (car (zmq--subprocess-read-output
                                 "(event . \"foo\")")))
                (should (equal sexp '(event . "foo")))
                (should (= (length (buffer-string)) 0))))
            (with-temp-buffer
              (ert-info ("Reading a partial sexp")
                (setq sexp (car (zmq--subprocess-read-output
                                 "(event . \"foo\"")))
                (should-not sexp))
              (ert-info ("Reading pending output from partial sexp")
                (let ((events (zmq--subprocess-read-output
                               ")(jelly . jam)")))
                  (should (= (length events) 2))
                  (should (equal (car events) '(event . "foo")))
                  (should (equal (cadr events) '(jelly . jam))))))
            (ert-info ("Invalid read syntax")
              (with-temp-buffer
                (should-error (zmq--subprocess-read-output
                               "(foo . bar)#()"))))
            (ert-info ("Ignoring raw text")
              (should-not (zmq--subprocess-read-output
                           "This is raw text"))
              (should (equal (car (zmq--subprocess-read-output
                                   "This is raw text 'foo"))
                             '(quote foo)))
              (should (equal (car (zmq--subprocess-read-output
                                   "This is raw text \"foo\""))
                             "foo"))))
          (ert-info ("Subprocess filter")
            (let ((filter-called nil))
              (process-put
               process :filter (lambda (event)
                                 (setq filter-called t)
                                 (should (equal event '(event . "foo")))))
              (zmq--subprocess-filter process "(event . \"foo\")")
              (should filter-called)
              ;; Subprocess sends errors which get emitted back to the parent
              ;; emacs process, see `zmq--init-subprocess'
              (should-error (zmq--subprocess-filter process "(error . \"foo\")")
                            :type 'zmq-subprocess-error))))
      (kill-process process))))

(provide 'zmq-tests)

;;; zmq-tests.el ends here
