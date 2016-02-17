#lang racket

(require "c.rkt")
(require "../test.rkt")
(require "../common.rkt")

(define *test-name* (make-parameter #f))

(define (allowed-tests bench-dir)
  (define tests (load-tests bench-dir))
  (if (*test-name*)
      (filter (λ (t) (equal? (*test-name*) (test-name test))) tests)
      tests))

(define (compile-single bench-file-or-dir output-prefix)
  (for ([test (allowed-tests bench-file-or-dir)])
    (write-file (string-append output-prefix (string-normalize-spaces (test-name test) #px"\\s+" "-") ".c")
                (if (test-output test)
                    (compile-all (test-name test) (test-program test)
                                 (test-target test) (test-target test) 3000)
                    (compile-all (test-name test) (test-program test)
                                 (test-program test) (test-program test) 3000)))))

(module+ main
  (require racket/cmdline)

  (command-line
   #:program "compile/c-single.rkt"
   #:once-each
   [("-t" "--test") test-name "Only use a single test from the bench file."
    (*test-name* test-name)]
   #:args (bench-file-or-dir output-prefix)
   (compile-single bench-file-or-dir output-prefix)))
