;;
;; field.lisp
;; Release: Field-6.0 (12/12/12)
;;
;; Contact: Cesar Munoz (cesar.a.munoz@nasa.gov)
;; NASA Langley Research Center
;; http://shemesh.larc.nasa.gov/people/cam/Field
;;
;; Copyright (c) 2011-2012 United States Government as represented by
;; the National Aeronautics and Space Administration.  No copyright
;; is claimed in the United States under Title 17, U.S.Code. All Other
;; Rights Reserved.
;;
;; Field is a simplification procedure for the field of reals.
;; This strategy was originally implemented with the collaboration of 
;; Micaela Mayero (Micaela.Mayero@inria.fr). 
;;
;; Strategies in Field:
(defparameter *field-strategies* "
%  field, grind-reals, real-props, 
%  neg-formula, add-formulas, sub-formulas,
%  cancel-by, cancel-formula,
%  both-sides-f, sq-simp")
;;

(defparameter *field-version* "Field-6.0 (12/12/12)")

(defun check-no-relation (fnum)
  (let* ((f   (extra-get-formula fnum))
	 (rel (is-relation f)))
    (cond ((not f) (msg-noformula fnum))
	  ((not rel) (msg-norelation fnum)))))

;; Message for an invalid arithmetic relational formula.
(defun msg-norelation (fnum)
  (msg-noformula fnum "arithmetic relational formula"))

;; Message for an invalid formula number.
(defun msg-noformula (fnum &optional (msg "formula"))
  (let ((fnums (extra-get-fnums fnum)))
     (format nil "No ~a~p found in ~{~a~^ or ~}." 
	    msg (length fnums) fnums)))

(defun ord2num (expr)
  (when expr
    (cond ((is-infix-operator expr '<)  -2)
	  ((is-infix-operator expr '<=) -1)
	  ((is-infix-operator expr '=)   0)
	  ((is-infix-operator expr '>=)  1)
	  ((is-infix-operator expr '>)   2))))

(defun num2ord (num)
  (when num
    (cond ((= num -2) "<")
	  ((= num -1) "<=")
	  ((= num 0) "=")
	  ((= num 1) ">=")
	  ((= num 2) ">"))))

(defun get-distrib-plus (l expr)
  (cond ((or (is-infix-operator expr '+)
	     (is-infix-operator expr '-))
	 (adjoin (expr2str expr) l :test #'string=))
	((is-infix-operator expr '/)
	 (get-distrib-expr (get-distrib-expr l (args1 expr))
			   (args2 expr)))
	((is-infix-operator expr '*)
	 (get-distrib-plus (get-distrib-plus l (args1 expr))
			   (args2 expr)))
	(t l)))

(defun get-distrib-expr (l expr)
  (cond ((or (is-infix-operator expr '+)
	     (is-infix-operator expr '-)
	     (is-infix-operator expr '/)
	     (is-relation expr))
	 (get-distrib-expr (get-distrib-expr l (args1 expr))
			   (args2 expr)))
	((is-prefix-operator expr '-)
	 (get-distrib-expr l (args1 expr)))
	((is-infix-operator expr '*)
	 (get-distrib-plus (get-distrib-plus l (args1 expr))
			   (args2 expr)))
	(t l)))

(defun get-distrib-formulas (l fnums)
  (when fnums
    (let ((formula (extra-get-formula (car fnums)))
	  (nl      (get-distrib-formulas l (cdr fnums))))
      (if formula
	  (get-distrib-expr nl formula)
	nl))))

(defun get-const-divisors (n polynom)
  (if polynom
      (let ((na (str2int (caar polynom))))
	(cond ((and na (> (cdar polynom) 0))
	       (get-const-divisors (* n na) (cdr polynom)))
	      (na
	       (get-const-divisors (/ n na) (cdr polynom)))
	      (t (get-const-divisors n (cdr polynom)))))
    n))

(defun un-polynom (polynom e)
  (when polynom
    (let* ((a  (caar polynom))
	   (na (str2int a))
	   (ne (str2int (car e)))
	   (b (cdar polynom))
	   (r (cdr polynom)))
      (cond ((and na ne)
	     (let ((g (lcm na ne)))
	       (if (= g 1) (in-polynom r e)
		 (cons (expr2str g) 1))))
	    ((or na ne)
	     (un-polynom r e))
	    ((string= a (car e))
	     (cons a (max b (cdr e))))
	    (t (un-polynom r e))))))

(defun union-polynom (polynom1 polynom2 l)
  (cond (polynom1
	 (let ((e (un-polynom polynom2 (car polynom1))))
	   (if e
	       (union-polynom (cdr polynom1) polynom2 (cons e l))
	     (union-polynom (cdr polynom1) polynom2 (cons (car polynom1) l)))))
	(polynom2
	 (let ((e (un-polynom l (car polynom2))))
	   (if e
	       (union-polynom polynom1 (cdr polynom2) l)
	     (union-polynom polynom1 (cdr polynom2) (cons (car polynom2) l)))))
	(t l)))

(defun get-divisors-monoms (l monoms)
  (if monoms
      (let* ((divmonom  (remove-if #'(lambda (x) (> (cdr x) 0))
				   (cancel-monom nil (car monoms) 1)))
	     (divpos    (mapcar #'(lambda (x) (cons (car x) (* -1 (cdr x))))
				divmonom)))
	(get-divisors-monoms (union-polynom l divpos nil) (cdr monoms)))
    l))

(defun get-divisors-formula (formula)
  (when (is-relation formula)
    (let ((monoms (get-monoms-formula formula)))
      (get-divisors-monoms nil monoms))))

(defun makeprod (divs names)
  (when divs
    (cons (cons (car names) (cdar divs))
	  (makeprod (cdr divs) (cdr names)))))

(defun get-monoms-expr (l expr)
  (cond ((or (is-infix-operator expr '+)
	     (is-infix-operator expr '-))
	 (get-monoms-expr (get-monoms-expr l (args1 expr))
			  (args2 expr)))
	((is-prefix-operator expr '-)
	 (get-monoms-expr l (args1 expr)))
	(t (cons expr l))))

(defun get-monoms-formula (formula)
  (when (is-relation formula)
    (get-monoms-expr (get-monoms-expr nil (args1 formula))
		     (args2 formula))))

(defun in-polynom (polynom e)
  (when polynom
    (let* ((a  (caar polynom))
	   (na (str2int a))
	   (ne (str2int (car e)))
	   (b (cdar polynom))
	   (r (cdr polynom)))
      (cond ((and ne (= ne 0)) e)
	    ((and na (= na 0)) e)
	    ((and na ne)
	     (let ((g (gcd na ne)))
	       (if (= g 1) (in-polynom r e)
		 (cons (expr2str g) 1))))
	    ((or na ne)(in-polynom r e))
	    ((string= a (car e))
	     (cons a (min b (cdr e))))
	    (t (in-polynom r e))))))

(defun inter-polynom (polynom1 polynom2 l)
  (if (and polynom1 polynom2)
      (let ((e (in-polynom polynom2 (car polynom1))))
	(if e
	    (inter-polynom (cdr polynom1) polynom2 (cons e l))
	  (inter-polynom (cdr polynom1) polynom2 l)))
    l))

;; Insert monomial in a list polynom = expr.expn representing a polynomial
;; If se = 1, monomial represents e
;; If se = -1, monomial represents 1/e
(defun insert-polynom (polynom e se)
  (let ((ne (str2int e)))
    (cond
     ((and ne (= ne 1)) polynom)
     (polynom
      (let* ((a  (caar polynom))
	     (na (str2int a))
	     (sa (cdar polynom)))
	(cond ((and ne na)
	       (cond ((> (* se sa) 0)
		      (insert-polynom (cdr polynom)
				      (expr2str (* na ne))
				      sa))
		     ((= na ne) (cdr polynom))
		     (t (let ((g (gcd ne na)))
			  (cond ((= na g)
				 (insert-polynom (cdr polynom)
						 (expr2str (/ ne g))
						 se))
				((= ne g)
				 (insert-polynom (cdr polynom)
						 (expr2str (/ na g))
						 sa))
				(t (cons (cons (expr2str (/ na g)) sa)
					 (insert-polynom (cdr polynom)
							 (expr2str (/ ne g))
							 se))))))))
	      (ne (cons (cons e se) polynom))
	      (na (cons (car polynom) (insert-polynom (cdr polynom) e se)))
	      ((string= e a)
	       (let ((count (+ se sa)))
		 (if (= count 0)
		     (cdr polynom)
		   (cons (cons e count) (cdr polynom)))))
	      ((> (length a) (length e))
	       (cons (cons e se) polynom))
	      (t (cons (car polynom) (insert-polynom (cdr polynom) e se))))))
     (t (list (cons e se))))))

(defun get-mults-monom (l expr)
  (cond ((is-infix-operator expr '*)
	 (get-mults-monom (get-mults-monom l (args1 expr)) (args2 expr)))
	((is-prefix-operator expr '-)
	 (get-mults-monom (insert-polynom l "-1" 1) (args1 expr)))
	(t (insert-polynom l (expr2str expr) 1))))

;; expr is expression
;; l a list (expr.expn) representing a polynomial that is being constructed
;; numden = 1 means expr, numdem = -1 means 1/expr
(defun cancel-monom (l expr numden)
  (cond ((is-infix-operator expr '/)
	 (cancel-monom (cancel-monom l (args1 expr) numden)
		       (args2 expr) (* -1 numden)))
	((is-infix-operator expr '*)
	 (cancel-monom (cancel-monom l (args1 expr) numden)
		       (args2 expr) numden))
	((is-prefix-operator expr '-)
	 (cancel-monom (insert-polynom l "-1" 1) (args1 expr) numden))
 	(t (insert-polynom l (expr2str expr) numden))))

(defun has-divisors (expr)
  (cond ((is-infix-operator expr '/) t)
	((or (is-infix-operator expr '+)
	     (is-infix-operator expr '-)
	     (is-infix-operator expr '*)
	     (is-relation expr))
	 (or (has-divisors (args1 expr))
	     (has-divisors (args2 expr))))
	((is-prefix-operator expr '-)
	 (has-divisors (args1 expr)))
	(t nil)))

(defun exp-n (e n)
  (cond ((= (abs n) 1) (format nil "~a" e))
	((> (abs n) 0) (format nil "~a * ~a" e
			       (exp-n e (- (abs n) 1))))
	(t "1")))

(defun normal-mult-parens (l)
  (cond ((= (length l) 1) (exp-n (caar l) (cdar l)))
	(t (format nil "~a * ~a"
		   (exp-n (caar l) (cdar l))
		   (normal-mult-parens (cdr l))))))

(defun normal-mult (l)
  (when l
    (cond ((not l) "1")
	  ((and (= (length l) 1)
		(= (abs (cdar l)) 1))
	   (caar l))
	  (t (format nil "(~a)" (normal-mult-parens l))))))

(defun normal-term (numden)
  (let ((num (mapcan #'(lambda (p) (and (> (cdr p) 0) (list p))) numden))
	(den (mapcan #'(lambda (p) (and (< (cdr p) 0) (list p))) numden)))
    (cond (numden
	   (cond (num
		  (cond (den (format nil "~a / ~a"
				     (normal-mult num)
				     (normal-mult den)))
			(t (normal-mult num))))
		 (t (format nil "1 / ~a" (normal-mult den)))))
	  (t "1"))))

(defun makecases-monoms (monoms)
  (loop for monom in monoms
	as cmonom = (let* ((cm (cancel-monom nil monom 1))
			   (nt (normal-term cm)))
		      nt)
	when (string/= (format nil "~a" monom) cmonom)
	collect (format nil "~a = ~a" monom cmonom)))

(defstrat name-distrib (&optional (fnums *) (prefix "ND") label hide? (step (subtype-tcc)))
  (let ((dist (get-distrib-formulas nil (extra-get-fnums fnums))))
    (when dist
      (let ((names   (freshnames prefix (length dist)))
	    (nameseq (merge-names-exprs names dist))
	    (lbl     (or label 'none)))
	(name-label* nameseq :label label :fnums fnums :hide? hide? :step step))))
  "[Field] Introduces new names, which are based on PREFIX, to block the automatic
application of distributive laws in formulas FNUMS. Labels as LABEL(s) the formulas
where new names are defined. These formulas are hidden if HIDE? is t. TCCs generated
during the execution of the command are discharged with the proof command STEP.")

(defstrat wrap-manip (fnum manip &optional (step (subtype-tcc)) (labels? t))
  (with-fnums
   ((!wmp fnum)
    (!wmd))
   (let ((labs (when labels? (extra-get-labels fnum))))
     (branch (discriminate
	      (let ((old *suppress-manip-messages*)
		     (xxx (setq *suppress-manip-messages* t)))
		(unwind-protect$
		 manip
		 (let ((xxx (setq *suppress-manip-messages* old))) (skip))))
	      !wmd :strict? t)
	     ((when labels? (relabel labs !wmd))
	      (finalize step)))))
  "[Field] Wraps Manip's command MANIP so that it is quiet, dicharges TCCs, and, when preserve? is t,
preserves labels of FNUM.")
  
(defstep neg-formula (&optional (fnum (+ -)) (hide? t) label (step (subtype-tcc)))
  (let ((fnexpr (first-formula fnum :test #'field-formula))
	(fn      (car fnexpr))
	(formula (cadr fnexpr))
	(rel     (is-relation formula)))
    (if rel
	(with-fnums
	 ((!ngf fn :tccs)
	  (!ngl)
	  (!ngo))
	 (protect
	  !ngf 
	  (then@
	   (if label
	       (relabel (!ngo label) !ngf :push? nil)
	     (relabel !ngo !ngf))
	   (wrap-manip !ngo (mult-by !ngo "-1" :sign -) :step step)
	   (real-props !ngo :simplify? t))
	  !ngl hide?))
      (printf "No arithmetic relational formula in ~a" fnum)))
  "[Field] Negates both sides of the relational formula FNUM. If HIDE? is t,
the original formula is hidden.  The new formula is labeled as the original
one, unless an explicit LABEL is provided. TCCs generated during the execution
of the command are discharged with the proof command STEP."
  "Negating relational formula ~a")

(defparameter *field-distrib* '("times_div1" "times_div2" "div_times"
				"add_div" "minus_div1" "minus_div2"
				"div_distributes" "div_distributes_minus"))

(defparameter *field-rewrites* '("times_plus" "div_simp" "div_cancel1" "div_cancel2"
				 "div_div1" "div_div2" 
				 "zero_times1" "zero_times2" "neg_times_neg"
				 "zero_is_neg_zero" "abs_mult" "abs_div" "abs_abs" "abs_square"
				 "times_div_cancel1" "times_div_cancel2"))

(defstep real-props (&optional (fnums *) theories simplify?
			       (let-reduce? t) (distrib? t))
  (let ((exclude (unless distrib? *field-distrib*))
	(realp   (if simplify?
		     (cons 'auto-rewrite (append *field-rewrites*
						 (when distrib?
						   *field-distrib*)))
		   (list 'auto-rewrite-theory "real_props" :exclude exclude))) 
	(th      (cons "extra_tegies" (enlist-it theories))))
    (with-fnums
     ((!rps fnums)
      (!rpd))
     (let ((step    (list 'then
			  realp
			  (cons 'auto-rewrite-theories th)
			  (list 'assert !rps :let-reduce? let-reduce?)
			  (cons 'stop-rewrite-theory (cons "real_props" th)))))
       (if distrib?
	   step
	 (then
	  (name-distrib fnums :label !rpd)
	  step
	  (replaces !rpd :dir rl :in !rps :but !rpd :hide? nil)
	  (hide !rpd))))))
  "[Field] Autorewrites with \"real_props\" and THEORIES in FNUMS. If SIMPLIFY? is t,
only basic rewrite rules are applied. If LET-REDUCE? is nil, let-in expressions will
not be reduced. If DISTRIB? is nil, distribution laws will not be applied."
  "Applying real-props")

(defstep grind-reals (&optional defs theories rewrites
				exclude (if-match t) (updates? t)
				polarity? (instantiator inst?)
				(let-reduce? t)
				dontdistrib protect)
  (with-fnums
   (!grd)
   (let ((th    (cons "real_props" (cons "extra_tegies" (enlist-it theories))))
	 (pro   (cons !grd (enlist-it protect)))
	 (step `(grind :defs ,defs :theories ,th :rewrites
		       ,rewrites :exclude ,exclude :if-match
		       ,if-match :updates? ,updates? :polarity?
		       ,polarity? :instantiator
		       ,instantiator :let-reduce? let-reduce?)))
     (then
      (when dontdistrib
	(name-distrib dontdistrib :label !grd))
      (finalize (assert))
      (protect pro step)
      (when dontdistrib
	(replaces !grd :dir rl :but !grd :hide? nil)
	(hide !grd)))))
  "[Field] Apply grind with \"real_props\". This strategy supports the same
options as grind. Additionally, grind-reals blocks distribution laws in main level
expressions in the list of formulas DONTDISTRIB and protects formulas in PROTECT."
  "Applying grind-reals")

(defstep add-formulas (fnum1 &optional fnum2 (hide? t) label (step (subtype-tcc)))
  (let ((fnum2    (or fnum2 fnum1))
	(f1       (extra-get-fnum fnum1))
	(f2       (extra-get-fnum fnum2))
	(eqfs     (or (and (numberp f1) (numberp f2) (= f1 f2))
		      (and (numberp fnum1) (numberp fnum2) (= fnum1 fnum2))))
	(formula1 (extra-get-formula-from-fnum f1))
	(formula2 (extra-get-formula-from-fnum f2))
    	(formsg   (if eqfs fnum1 (list fnum1 fnum2)))
	(rel1     (is-relation formula1))
	(rel2     (is-relation formula2))
	(o1       (ord2num formula1))
	(o2       (ord2num formula2)))
    (if (and o1 o2)
	(let ((flag  (>= (* f1 f2 o1 o2) 0))
	      (f11   (args1 formula1))
	      (f12   (if flag 
			 (args1 formula2)
		       (args2 formula2)))
	      (f21   (args2 formula1))
	      (f22   (if flag 
			 (args2 formula2)
		       (args1 formula2)))
	      (op    (num2ord (new-relation f1 f2 o1 o2)))
	      (str   (when op (format nil "~a ~a ~a"
				      (mk-application '+ f11 f12) op
				      (mk-application '+ f21 f22))))
	      (labad (or label (freshlabel "AD"))))
	  (with-fnums
	   ((!ad1 f1 :tccs)
	    (!ad2 f2 :tccs))
	   (discriminate (case str) labad)
	   (else (finalize (real-props (!ad1 !ad2 labad)))
		 (real-props (!ad1 !ad2 labad) :simplify? t))
	   (unless label (delabel labad))
	   (when hide? (hide (!ad1 !ad2))))) 
      (printf "No arithmetic relational formulas in ~a" formsg)))
  "[Field] Adds relational formulas FNUM1 and FNUM2. If FNUM2 is nil, adds FNUM to itself.
If HIDE? is t, the original formulas are hidden.  The new formula is labeled as LABEL,
if specified. TCCs generated during the execution of the command are discharged with
the proof command STEP."
  "Adding formulas ~a and ~:[~@*~a~;~:*~a~]")

(defstep sub-formulas (fnum1 fnum2 &optional (hide? t) label (step (subtype-tcc)))
  (let ((f1       (extra-get-fnum fnum1))
	(f2       (extra-get-fnum fnum2))
	(eqfs     (or (and (numberp f1) (numberp f2) (= f1 f2))
		      (and (numberp fnum1) (numberp fnum2) (= fnum1 fnum2))))
	(formula1 (extra-get-formula-from-fnum f1))
	(formula2 (extra-get-formula-from-fnum f2))
	(rel1     (is-relation formula1))
	(rel2     (is-relation formula2))
	(o1       (ord2num formula1))
	(o2       (ord2num formula2))
	(labsb    (or label (freshlabel "SB"))))
    (if eqfs
	(printf "Formula ~a cannot be subtracted from itself" fnum1)
      (if (and o1 o2)
	  (with-fnums
	   ((!sb1 f1 :tccs)
	    (!sb2 f2 :tccs)
	    (!nsb2)
	    (!nlb))
	   (protect
	    !sb2
	    (then (then@ (neg-formula !sb2 :label !nsb2 :step step)
			 (add-formulas !sb1 !nsb2 :hide? nil :label labsb))
		  (unless label (delabel labsb))
		  (delete !nsb2)
		  (when hide? (hide !sb1)))
	    !nlb
	    hide?))
	(printf "No arithmetic relational formulas in (~a ~a)" fnum1 fnum2))))
  "[Field] Subtracts relational formulas FNUM1 and FNUM2. If HIDE? is t,
the original formulas are hidden.  The new formula is labeled as LABEL,
if specified. TCCs generated during the execution of the command are discharged
with the proof command STEP."
  "Substracting relational formulas ~a and ~a")

(defhelper cases-monoms__ (label cases step)
  (if cases
      (let ((frel  (car cases))
	    (frels (cdr cases)))
	   (branch (case frel)
		   ((then (replaces -1 label)
			  (cases-monoms__$ label frels step))
		    (then (delete label)
			  (grind-reals))
		    (finalize step))))
      (assert label))
  "[Field] Internal strategy." "")

(defhelper simplify-monoms__ (label step)
  (let ((flag (has-divisors (extra-get-formula label))))
    (when flag
      (assert label)
      (let ((formula (extra-get-formula label))
	    (monoms  (get-monoms-formula formula))
	    (cases   (makecases-monoms monoms)))
	(cases-monoms__$ label cases step))))
  "[Field] Internal strategy." "")

(defstep cancel-by (fnum expr &optional theories (step (subtype-tcc)))
  (let ((fnexpr   (first-formula fnum :test #'field-formula))
	(fn       (car fnexpr))
	(formula  (cadr fnexpr))
	(rel      (is-relation formula))
	(expstr   (extra-get-expstr expr))
	(div      (freshname "CBD")))
    (if (and rel expstr)
	(with-fnums
	 ((!cby fn)
	  (!cbt)
	  (!cbd)
	  (!cbdt)
	  (!ndc))
	 (tccs-formula !cby :label !cbt)
	 (branch (then@ (tccs-expr expstr :label !cbdt :step step)
			(name-label div expstr :label !cbd :step step)
			(name-distrib (!cby !cbd !cbt !cbdt) :prefix "NDC" :label !ndc :step step))
		 ((cancel-by__$ !cby !cbd !ndc div theories step)
		  (delete !cby)))
	 (delete (!cbt !cbdt)))
      (if (not rel)
	  (printf "No arithmetic relational formula in ~a" fnum)
	(if (not expstr)
	    (printf "No suitable expression ~a" expr)))))
  "[Field] Cancels the common expression EXPR in the relational formula FNUM.
Autorewrites with THEORIES when possible. TCCs generated during the execution
of the command are discharged with the proof command STEP."
  "Canceling in formula ~a with ~a")

(defhelper cancel-case__ (labcb labdiv labndc inv_div theories step &optional (sign +))
  (then@
   (wrap-manip labcb (mult-by labcb inv_div sign) :step step)
   (replaces labdiv :dir rl :hide? nil)
   (hide labdiv)
   (simplify-monoms__$ labcb step)
   (replaces labndc :but labndc :dir rl :hide? nil)
   (hide labndc)
   (real-props labcb :theories theories :distrib? nil)
   (finalize (grind-reals :theories theories :dontdistrib labcb)))
  "[Field] Internal strategy." "")

(defhelper guess_cancel_by__ (labcb labdiv theories)
  (finalize
   (then (delete labcb)
	 (replaces labdiv :dir rl :hide? nil)
	 (grind-reals :theories theories)))
  "[Field] Internal strategy." "")

(defhelper cancel-by__ (labcb labdiv labndc div theories step)
  (let ((nz_div  (format nil "~a = 0" div))
        (inv_div (format nil "1 / ~a" div))
	(gt0_div (format nil "~a > 0" div))
	(is_eq   (equation? (extra-get-formula labcb))))
    (branch
     (case nz_div)
     ((then@ (replace labdiv :dir rl)
	     (hide labdiv)
	     (real-props :theories theories)
	     (replaces labndc :but labndc :dir rl :hide? nil)
	     (hide labndc))
      (if is_eq
	  (cancel-case__$ labcb labdiv labndc inv_div theories step)
	(branch
	 (case gt0_div)
	 ((then@ (guess_cancel_by__$ labcb labdiv theories)
		 (cancel-case__$ labcb labdiv labndc inv_div theories step +))
	  (then@ (guess_cancel_by__$ labcb labdiv theories)
		 (cancel-case__$ labcb labdiv labndc inv_div theories step -))
	  (finalize step))))
      (finalize step))))
  "[Field] Internal strategy." "")

(defstep cancel-formula (&optional (fnum + -) theories (step (subtype-tcc)))
  (let ((fnexpr  (first-formula fnum :test #'field-formula))
	(fn      (car fnexpr))
	(formula (cadr fnexpr))
	(rel     (is-relation formula)))
    (if rel
	(with-fnums
	 (!cf fn)
	 (try (wrap-manip !cf (factor !cf) :step step)
	      (let ((form (extra-get-formula !cf))
		    (l1   (get-mults-monom nil (args1 form)))
		    (l2   (get-mults-monom nil (args2 form)))
		    (l    (inter-polynom l1 l2 nil))
		    (cb   (normal-mult l)))
		(if cb
		    (cancel-by !cf cb :theories theories :step step)
		  (finalize (grind-reals :theories theories :dontdistrib !cf))))
	      (finalize (grind-reals :theories theories :dontdistrib !cf))))
      (printf "No arithmetic relational formula in ~a" fnum)))
  "[Field] Factorizes common terms in FNUM and then cancels them. Autorewrites with
THEORIES when possible. TCCs generated during the execution of the
command are discharged with the proof command STEP."
  "Canceling formula ~a")

(defhelper field__ (labfd labndf labx theories cancel? step)
  (then@
   (simplify-monoms__$ labfd step)
   (let ((form     (extra-get-formula labfd))
	 (is_eq    (equation? form))
	 (divs     (get-divisors-formula form))
	 (ndivs    (get-const-divisors 1 divs))
	 (edivs    (remove-if #'(lambda (x) (str2int (car x))) divs)))
     (if divs
	 (let ((names    (freshnames "FDX" (length edivs)))
	       (nameseq  (merge-names-exprs names
					    (mapcar #'(lambda(x) (car x))
						    edivs)))
	       (eprod    (makeprod edivs names))
	       (prod     (normal-mult (if (= ndivs 1) eprod
					(cons (cons (expr2str ndivs) 1)
					      eprod))))
	       (prodgt0  (format nil "~a > 0" prod)))
	   (spread (name-label* nameseq :label labx :step step)
		   ((if is_eq
			(then@ (wrap-manip labfd (mult-by labfd prod) :step step)
			       (field__$ labfd labndf labx theories cancel? step))
		      (branch (case prodgt0)
			      ((then@
				(finalize (then (delete labfd) (grind-reals :theories theories)))
				(wrap-manip labfd (mult-by labfd prod +) :step step)
				(field__$ labfd labndf labx theories cancel? step))
			       (then@
				(finalize (then (delete labfd) (grind-reals :theories theories)))
				(wrap-manip labfd (mult-by labfd prod -) :step step)
				(field__$ labfd labndf labx theories cancel? step))
			       (finalize step)))))))
       (try (replaces labx :but labx :dir rl :hide? nil)
	    (then@ (delete labx)
		   (field__$ labfd labndf labx theories cancel? step))
	    (try (replaces labndf :but labndf :dir rl :hide? nil)
		 (then@ (delete labndf)
			(field__$ labfd labndf labx theories cancel? step))
		 (then  (real-props labfd :theories theories :distrib? cancel?)
			(if cancel?
			    (cancel-formula labfd :theories theories :step step)
			  (finalize (grind-reals :theories theories :dontdistrib labfd)))))))))
  "[Field] Internal strategy." "")

(defun field-formula (fn expr)
  (is-relation expr))

(defstep field (&optional (fnum (+ -)) theories cancel? (step (subtype-tcc)))
  (let ((fnexpr  (first-formula fnum :test #'field-formula))
	(fn      (car fnexpr))
	(formula (cadr fnexpr))
	(rel     (is-relation formula)))
    (if rel
	(with-fnums
	 ((!fd fn)
	  (!fdt)
	  (!ndf)
	  (!x))
	 (tccs-formula !fd :label !fdt)
	 (branch (name-distrib (!fd !fdt) :prefix "NDF" :label !ndf :step step)
		 ((field__$ !fd !ndf !x theories cancel? step)
		  (delete !fd)))
	 (delete !fdt))
      (printf "No arithmetic relational formula in ~a" fnum)))
  "[Field] Removes divisions and apply simplification heuristics to the relational
formula on real numbers FNUM. It autorewrites with THEORIES when possible. If CANCEL?
is t, then it tries to cancel common terms once the expression is free of divisions.
TCCs generated during the execution of the command are discharged with the proof command STEP."
  "Removing divisions and simplifying formula ~a with field")

(defstep sq-simp (&optional (fnum *))  
  (rewrite* ("sq_0" "sq_1" "sq_abs" "sq_abs_neg" "sq_neg" "sq_times" "sq_plus" "sq_minus"
  	     "sq_div" "sqrt_0" "sqrt_1" "sqrt_def" "sqrt_square"
             "sqrt_sq" "sq_sqrt" "sqrt_times" "sqrt_div" "sqrt_sq_abs") fnum)
  "[Field] Simplifies FNUM with lemmas from sq and sqrt."
  "Simplifying sq and sqrt in ~a")

(defstep both-sides-f (fnum f &optional (hide? t) label (step (subtype-tcc)))
  (let ((fnexpr  (first-formula fnum :test #'field-formula))
	(fn      (car fnexpr))
	(formula (cadr fnexpr))
	(rel     (is-relation formula))
	(str     (format nil "~a(%1)" f))
	(lbs     (or label (extra-get-labels-from-fnum fn))))
    (if rel
	(with-fnums
	 ((!bsf fn :tccs)
	  (!bsp)
	  (!bsl))
	 (spread (discriminate (wrap-manip !bsf (transform-both !bsf str) :step step :labels? nil) !bsl)
		 ((then (delabel !bsf hide?) (finalize step))))
	 (relabel lbs !bsl :push? nil))
      (printf "No arithmetic relational formula in ~a" fnum)))
  "[Field] Applies function F to both sides of the relational expression in FNUM. If
HIDE? is t, the original formula is hidden. The new formulas are labeled as the original
one, unless an explicit LABEL is provided. TCCs generated during the execution of the
command are discharged with the proof command STEP."
  "Applying ~1@*~a to both sides of formula ~@*~a")

(defstrat wrap-formula (fnum f)
  (both-sides-f fnum f)
  "[Field] Obsolete strategy. Use both-sides-f.")

(defstrat field-about ()
  (let ((version *field-version*)
	(strategies *field-strategies*))
    (printf "%--
% ~a 
% http://shemesh.larc.nasa.gov/people/cam/Field
% Strategies in Field:~a
%--~%" version strategies))
  "[Field] Prints Field's about information.")

