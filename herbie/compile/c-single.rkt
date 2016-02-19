#lang racket

(require "c.rkt")
(require "../test.rkt")
(require "../common.rkt")
(require "../points.rkt")
(require "../programs.rkt")
(require "../config.rkt")

(define *test-name* (make-parameter #f))
(define *mk-points* (make-parameter #f))
(define *mk-prog* (make-parameter #f))
(define *num-pts* (make-parameter 8000))

(define (allowed-tests bench-dir)
  (define tests (load-tests bench-dir))
  (if (*test-name*)
      (filter (λ (t) (equal? (*test-name*) (test-name t))) tests)
      tests))

(define (compile-single bench-file-or-dir output-prefix)
  (for ([test (allowed-tests bench-file-or-dir)])
    (let ([nname (string-normalize-spaces (test-name test) #px"\\s+" "-")])
      (when (not (or (*mk-prog*) (*mk-points*)))
        (printf "Hey! Use --pts or --prog to make me do something."))
      (when (*mk-prog*)
        (printf "Outputting test ~a~n" nname)
        (write-file (string-append output-prefix nname ".c")
                    (if (test-output test)
                        (compile-all (test-name test) (test-program test)
                                     (test-target test) (test-target test) 3000)
                        (compile-all (test-name test) (test-program test)
                                     (test-program test) (test-program test) 3000))))
      (when (*mk-points*)
        (printf "Making ~a points~n" (*num-pts*))
        (write-file (string-append output-prefix nname "-pts.c")
                    (print-c-points (*num-pts*) (test-samplers test) (test-program test)))))))

(define (print-c-points npts samplers prog)
  (let ([cntxt (parameterize ([*num-points* npts])
                 (prepare-points prog samplers))])
    (printf "~n")
    (printf "double pts[~a][~a] =~n" npts (length (program-variables prog)))
    (printf "  {~n")
    (for ([(pt ex) (in-pcontext cntxt)])
      (printf "    {")
      (for ([coord pt])
        (printf "~a," coord))
      (printf "},~n"))
    (printf "  };~n")))

(module+ main
  (require racket/cmdline)

  (command-line
   #:program "compile/c-single.rkt"
   #:once-each
   [("-t" "--test") test-name "Only use a single test from the bench file."
    (*test-name* test-name)]
   [("--pts") "Output points to a c file."
    (*mk-points* #t)]
   [("--prog") "Output program to a c file."
    (*mk-prog* #t)]
   [("-n" "--num-points") num-pts "How many points to use"
    (*num-pts* (string->number num-pts))]
   #:args (bench-file-or-dir output-prefix)
   (compile-single bench-file-or-dir output-prefix)))
