#lang racket

(require math/flonum)
(require math/bigfloat)
(require herbie/common)
(require herbie/programs)
(require herbie/config)

(provide *pcontext* in-pcontext mk-pcontext pcontext?
	 sample-expbucket sample-double sample-float sample-uniform sample-integer sample-default
         prepare-points prepare-points-period make-exacts
         errors errors-score sorted-context-list)

(define *pcontext* (make-parameter #f))

(struct pcontext (points exacts))

(define (in-pcontext context)
  (in-parallel (in-vector (pcontext-points context)) (in-vector (pcontext-exacts context))))

(define (mk-pcontext points exacts)
  (pcontext (if (list? points)
		(begin (assert (not (null? points)))
		       (list->vector points))
		(begin (assert (not (= 0 (vector-length points))))
		       points))
	    (if (list? exacts)
		(begin (assert (not (null? exacts)))
		       (list->vector exacts))
		(begin (assert (not (= 0 (vector-length exacts))))
		       exacts))))

(define (sorted-context-list context vidx)
  (let ([p&e (sort (for/list ([(pt ex) (in-pcontext context)]) (cons pt ex))
		   < #:key (compose (curryr list-ref vidx) car))])
    (list (map car p&e) (map cdr p&e))))

(define (sample-expbucket num)
  (let ([bucket-width (/ (- 256 2) num)]
        [bucket-bias (- (/ 256 2) 1)])
    (for/list ([i (range num)])
      (expt 2 (- (* bucket-width (+ i (random))) bucket-bias)))))

(define (random-single-flonum)
  (floating-point-bytes->real (integer->integer-bytes (random-exp 32) 4 #f)))

(define (random-double-flonum)
  (floating-point-bytes->real (integer->integer-bytes (random-exp 64) 8 #f)))

(define (sample-float num)
  (for/list ([i (range num)])
    (real->double-flonum (random-single-flonum))))

(define (sample-double num)
  (for/list ([i (range num)])
    (real->double-flonum (random-double-flonum))))

(define (sample-default n) (((flag 'sample 'double) sample-double sample-float) n))

(define ((sample-uniform a b) num)
  (build-list num (λ (_) (+ (* (random) (- b a)) a))))

(define (sample-integer num)
  (build-list num (λ (_) (- (random-exp 32) (expt 2 31)))))

(define (make-period-points num periods)
  (let ([points-per-dim (floor (exp (/ (log num) (length periods))))])
    (apply list-product
	   (map (λ (prd)
		  (let ([bucket-width (/ prd points-per-dim)])
		    (for/list ([i (range points-per-dim)])
		      (+ (* i bucket-width) (* bucket-width (random))))))
		periods))))

(define (select-every skip l)
  (let loop ([l l] [count skip])
    (cond
     [(null? l) '()]
     [(= count 0)
      (cons (car l) (loop (cdr l) skip))]
     [else
      (loop (cdr l) (- count 1))])))

(define (make-exacts* prog pts)
  (let ([f (eval-prog prog mode:bf)] [n (length pts)])
    (let loop ([prec (- (bf-precision) (*precision-step*))]
               [prev #f])
      (bf-precision prec)
      (let ([curr (map f pts)])
        (if (and prev (andmap =-or-nan? prev curr))
            curr
            (loop (+ prec (*precision-step*)) curr))))))

(define (make-exacts prog pts)
  (define n (length pts))
  (let loop ([n* 16]) ; 16 is arbitrary; *num-points* should be n* times a power of 2
    (cond
     [(>= n* n)
      (make-exacts* prog pts)]
     [else
      (make-exacts* prog (select-every (round (/ n n*)) pts))
      (loop (* n* 2))])))

(define (filter-points pts exacts)
  "Take only the points for which the exact value is normal, and the point is normal"
  (reap (sow)
    (for ([pt pts] [exact exacts])
      (when (and (ordinary-float? exact) (andmap ordinary-float? pt))
        (sow pt)))))

(define (filter-exacts pts exacts)
  "Take only the exacts for which the exact value is normal, and the point is normal"
  (reap (sow)
    (for ([pt pts] [exact exacts])
      (when (and (ordinary-float? exact) (andmap ordinary-float? pt))
	(sow exact)))))

; These definitions in place, we finally generate the points.

(define (prepare-points prog samplers)
  "Given a program, return two lists:
   a list of input points (each a list of flonums)
   and a list of exact values for those points (each a flonum)"

  ; First, we generate points;
  (let loop ([pts '()] [exs '()])
    (if (>= (length pts) (*num-points*))
        (mk-pcontext (take pts (*num-points*)) (take exs (*num-points*)))
        (let* ([num (- (*num-points*) (length pts))]
               [pts1 (flip-lists (for/list ([rec samplers]) ((cdr rec) num)))]
               [exs1 (make-exacts prog pts1)]
               ; Then, we remove the points for which the answers
               ; are not representable
               [pts* (filter-points pts1 exs1)]
               [exs* (filter-exacts pts1 exs1)])
          (loop (append pts* pts) (append exs* exs))))))

(define (prepare-points-period prog periods)
  (let* ([pts (make-period-points (*num-points*) periods)]
	 [exacts (make-exacts prog pts)]
	 [pts* (filter-points pts exacts)]
	 [exacts* (filter-exacts pts exacts)])
    (mk-pcontext pts* exacts*)))

(define (errors prog pcontext)
  (let ([fn (eval-prog prog mode:fl)]
	[max-ulps (expt 2 (*bit-width*))])
    (for/list ([(point exact) (in-pcontext pcontext)])
      (let ([out (fn point)])
	(add1
	 (if (real? out)
	     (abs (ulp-difference out exact))
	     max-ulps))))))

(define (errors-score e)
  (let-values ([(reals unreals) (partition ordinary-float? e)])
    (if ((flag 'reduce 'avg-error) #f #t)
        (apply max (map ulps->bits reals))
        (/ (+ (apply + (map ulps->bits reals))
              (* (*bit-width*) (length unreals)))
           (length e)))))