;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; -*- Mode: Lisp -*- ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; translate-to-yices.lisp -- 
;; Author          : N. Shankar
;; Created On      : 
;; Last Modified By: N. Shankar
;; Last Modified On: 
;; Update Count    : 
;; Status          : Stable
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; --------------------------------------------------------------------
;; PVS
;; Copyright (C) 2006, SRI International.  All Rights Reserved.

;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 2
;; of the License, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
;; --------------------------------------------------------------------

(in-package :pvs)

;;NSH(3/17/06): Adapting translate-to-prove to yices output. 

(defvar *ybindings* nil)
(defvar *yembeddedf* nil)
(defvar *ydefns* nil)
(defvar *yname-hash* (make-pvs-hash-table))
(defvar *translate-to-yices-hash* (make-pvs-hash-table)
(defvar *yices-call* "/homes/demoura/project/yices/bin/x86_64-unknown-linux-gnu-release/yices")
(defvar *yices-id-counter*)  ;;needs to be initialized in eproofcheck
(newcounter *yices-id-counter*)

(defparameter *yices-interpreted-names*
  '((=  (equalities . =))
    (/=  (notequal . /=))
    (TRUE (booleans . true))
    (FALSE (booleans . false))
    (IMPLIES  (booleans . =>))
    (AND (booleans . and))
    (OR  (booleans . or) (bv_bitwise . bv-or))
    (NOT  (|booleans| . not)(bv_bitwise . bv-not))
    (+  (|number_fields| . +)(bv_arith_nat . bv-add))
    (- (number_fields . -)(bv_arithmetic . bv-sub))
    (*   (number_fields . *))
    (/  (number_fields . /))
    (rem (|modulo_arithmetic| . mod))
    (ndiv (|modulo_arithmetic| . div))
    (< (|reals| . <)(bv_arith_nat . bv-lt))
    (<=  (|reals| . <=)(bv_arith_nat . bv-le))
    (> (|reals| . >)(bv_arith_nat . bv-gt))
    (>=  (|reals| . >=)(bv_arith_nat . bv-ge))
    (o (|bv_concat_def| . bv-concat))
    (& (|bv_bitwise| . bv-and))
    (XOR  (|bv_bitwise| . bv-xor))
    (|bv^|  (|bv_caret| .  bv-extract))
    (sign_extend   (|bv_extend| . bv-sign-extend))
    ))

(defun clear-yices ()
  (setq *ydefns* nil)
  (clrhash *yname-hash*)
  (clrhash *translate-to-yices-hash*)
  (newcounter *yices-id-counter*))


;;We need to add constant declarations and type declarations.
;;Type definitions will be needed for scalars and datatypes.

;; (defstruct ytype (name def))
;; (defstruct yconst (name type))

(defun yices-name (expr &optional id) ;;expr must have id field,
                                      ;;or be given one
  (let ((entry (gethash expr *yname-hash*)))
    (or entry
	(let ((name (yices-id-name (or id (id expr)))))
	  (setf (gethash expr *yname-hash*) name)
	  name))))

(defun yices-id-name (id)
  (intern
   (concatenate 'string
     (string (if (integerp id)
		 (format nil "~r"
		   id)
		 id))
     "_"
     (princ-to-string
      (funcall
       *yices-id-counter*)))))

;;Next, we translate PVS types to Yices types so that any enumerated
;;types or datatypes introduce names.

(defun yices-type-name (expr)
  (yices-name expr))

(defun translate-to-yices-scalar-constructors (constructors)
  (loop for constr in constructors collect (yices-name constr)))

(defun translate-to-yices-scalar (yices-type-name constructors)
  (let ((yices-constructors
	 (translate-to-yices-scalar-constructors constructors)))
    (push (format nil "(define-type ~a (scalar ~{~a ~}))"
	    yices-type-name yices-constructors)
	  *ydefns*)
    (loop for cnstr in constructors
	  do (let* ((recognizer (recognizer cnstr))
		    (yices-recognizer (yices-name recognizer)))
	       (push (format nil "(define ~a::(-> x::~a bool) (lambda (x::~a) (x = ~a)))" 
		       yices-recognizer
		       yices-type-name
		       yices-type-name
		       (yices-name cnstr))
		     *ydefns*)))
    yices-type-name))


(defun translate-to-yices-accessors (accessors bindings)
  (cond ((consp accessors)
	 (format nil "~a::~a ~a"
	   (yices-name (car accessors))
	   (translate-to-yices* (range (type (car accessors))) bindings)
	   (translate-to-yices-accessors (cdr accessors) bindings)))
	(t (format nil ""))))

(defun translate-to-yices-constructor (constructor bindings)
  (let ((accessors (accessors constructor)))
    (if accessors 
	(format nil "(~a ~a)"
	  (yices-name constructor)
	  (translate-to-yices-accessors (accessors constructor) bindings))
	(format nil "~a" (yices-name constructor)))))

(defun translate-to-yices-constructors (constructors bindings)
  (cond ((consp constructors)
	 (cons (translate-to-yices-constructor (car constructors) bindings)
	       (translate-to-yices-constructors (cdr constructors) bindings)))
	(t nil)))

(defmethod translate-to-yices* ((ty type-name) bindings)
  (let ((yname-hash (gethash ty *yname-hash*)))
    (or yname-hash 
	(cond ((enum-adt? ty)
	       (let ((constructors (constructors ty))
		     (yices-name (yices-type-name ty)))	;;bindings can be ignored
		 (translate-to-yices-scalar yices-name constructors) ))
	      ((adt? ty)
	       (let ((constructors (constructors ty))
		      (yices-name (yices-type-name ty)))
		  (let ((defn-string
			  (format nil "(define-type ~a (datatype ~{~a ~}))"
			    yices-name
			    (translate-to-yices-constructors constructors bindings))))
		    (push defn-string *ydefns*)
		    yices-name)))
	      ((tc-eq (find-supertype ty) *boolean*)
	       (format nil "bool"))
	      (
		;;else uninterpreted type
		(let ((yices-name (yices-type-name ty)))
		  (push (format nil "(define-type ~a)" yices-name) *ydefns*)
		  yices-name))))))

(defmethod translate-to-yices* ((ty datatype-subtype) bindings)
  (let ((yname-hash (gethash ty *yname-hash*)))
    (or yname-hash 
	(let* ((supertype (supertype ty))
	       ;;(id (id supertype))
	       (ytypename (yices-type-name ty))
	       (constructors (constructors ty))
	       (defn-string
		 (format nil "(define-type ~a (datatype ~{~a ~}))"
		   ytypename
		   (translate-to-yices-constructors constructors bindings))))
	  (push defn-string *ydefns*)
	  ytypename))))
    


    ;;Not used
(defun subrange-range (type)
  (let ((below (simple-below? type)))
    (or (and below
	     (cons 0 below))
	(let ((upto (simple-upto? type)))
	  (or (and upto (cons 0 upto))
	      (simple-subrange? type))))))

(defun yices-format-tuple-list (id len)
  (loop for i  from 0 to (1- len)
	collect (format nil "(select ~a ~a)" id i)))

(defmethod translate-to-yices* ((ty subtype) bindings)
  (with-slots (supertype predicate) ty
    (cond ((tc-eq ty *naturalnumber*) 'nat)
	  ((tc-eq ty *integer*) 'int)
	  ((tc-eq ty *real*) 'real)
	  (t (let* ((ypred (translate-to-yices* predicate bindings))
		    (ysupertype (translate-to-yices* supertype
						     bindings))
		    (maxtype (find-supertype supertype))
		    (subvar (yices-id-name 'subvar)))
	       (if (tupletype? maxtype)
		   (let* ((ldom (length (types maxtype)))
			  (subvarlist (yices-format-tuple-list subvar ldom)))
		     (format nil "(subtype (~a::~a) (~a ~{~a~}))"
		       subvar ysupertype ypred subvarlist))
		   (format nil "(subtype (~a::~a) (~a ~a))"
		     subvar ysupertype ypred subvar)))))))

(defmethod translate-to-yices* ((ty tupletype) bindings)
  (format nil "(tuple ~{~a ~})" (translate-to-yices-list (types ty) nil nil bindings)))

;; (defmethod translate-to-yices* ((ty list) bindings)
;;   (translate-to-yices-list ty nil nil bindings))

(defun translate-to-yices-funlist (list accum num lastelem domvar
					bindings funbindings)
  (if (consp list)
      (if (or (bind-decl? (car list))
	      (dep-binding? (car list)))
      (translate-to-yices-funlist (cdr list)
			       (cons (translate-to-yices* (car list)
							  bindings)
				     accum)
			       (1+ num)
			       lastelem domvar
			       (cons (cons (car list)
					   (yices-name (car list)))
				     bindings)
			       (cons (cons (car list)
					   (format nil
					       "(select ~a ~a)"
					     domvar num))
				     bindings))
      (translate-to-yices-funlist (cdr list)
				  (cons (translate-to-yices* (car list)
							  bindings)
				     accum)
			       (1+ num)
			       lastelem domvar
			       bindings
			       bindings))
      (if lastelem
	  (format nil "(-> ~a::(tuple ~{ ~a~}) ~a)"
	    domvar (nreverse accum)
	    (translate-to-yices* lastelem funbindings))
	  (format nil "(tuple ~{ ~a~})" 
	  (nreverse accum)))))

(defun translate-to-yices-list (list accum lastelem bindings)
  (if (consp list)
      (translate-to-yices-list (cdr list)
			       (cons (translate-to-yices* (car list)
							  bindings)
				     accum)
			       lastelem
			       (if (or (bind-decl? (car list))
				       (dep-binding? (car list)))
				   (cons (cons (car list)
					       (yices-name (car list)))
					 bindings)
				   bindings))
      (if lastelem
	  (nreverse (cons (translate-to-yices* lastelem bindings)
			  accum))
	  (nreverse accum))))

(defmethod translate-to-yices* ((ty recordtype) bindings)
  (format nil "(record ~{~a ~})"
    (translate-to-yices-list (fields ty) nil nil bindings)))

(defmethod translate-to-yices* ((ty field-decl) bindings)
  (format nil "~a::~a" (id ty)
	  (translate-to-yices* (type ty) bindings)))

(defmethod translate-to-yices* ((ty dep-binding) bindings)
  (let ((yices-id (yices-name ty))
	(yices-type (translate-to-yices* (type ty) bindings)))
    (format nil "~a::~a" yices-id yices-type)))

(defmethod translate-to-yices* ((ty funtype) bindings)
  (with-slots (domain range) ty
    (if (tupletype? domain)
	(translate-to-yices-funlist (types domain) nil  1 range
				    (yices-id-name "domvar")
				    bindings bindings)
	(format nil "(-> ~a ~a)" 
	  (translate-to-yices* domain bindings)
	  (translate-to-yices* range
			       (if (dep-binding? domain)
				   (cons (cons domain
					       (yices-name domain))
					 bindings)
				   bindings))))))



		     

;;name-exprs and binding-exprs are not hashed in binding contexts.
;;*bound-variables* are the bound variables in the calling context, and
;;*bindings* are the ones built up locally.
(defmethod translate-to-yices* :around ((obj type-expr) bindings)
	   (if (or *bound-variables* *bindings*)
	       (call-next-method)
	       (let ((hashed-value (gethash obj *translate-to-yices-hash*)))
		 (or hashed-value
		     (let ((result (call-next-method)))
		       (setf (gethash obj *translate-to-yices-hash*)
			     result)
		       result)))))
    
(defmethod translate-to-yices* :around ((obj name-expr) bindings)
	   (if (or *bound-variables* *bindings*)
	       (call-next-method)
	       (let ((hashed-value (gethash obj *translate-to-yices-hash*)))
		 (or hashed-value
		     (let ((result (call-next-method)))
		       (setf (gethash obj *translate-to-yices-hash*)
			     result)
		       result)))))

(defmethod translate-to-yices* :around ((obj binding-expr) bindings)
	   (if (or *bound-variables* *bindings*)
	       (call-next-method)
	       (let ((hashed-value
		      (gethash obj *translate-to-yices-hash*)))
		 (or hashed-value
		     (let ((result (call-next-method)))
		       (setf (gethash obj *translate-to-yices-hash*)
			     result)
		       result)))))

(defmethod translate-to-yices* ((list list) bindings)
  (cond ((consp list)
	 (cons (translate-to-yices* (car list) bindings)
	       (translate-to-yices* (cdr list) bindings)))
	(t nil)))

(defun yices-recognizer (name bindings)
  (and (recognizer? name)
       (format nil "~a?" (translate-to-yices* (constructor name) bindings) )))


(defmethod translate-to-yices* ((expr name-expr) bindings)
  (let ((bpos (assoc expr bindings
		     :test #'same-declaration)))
    (if bpos (cdr bpos)
	(let* ((yname-hashentry (gethash expr *yname-hash*)))
	  (or yname-hashentry
	      (yices-interpretation expr)
	      (yices-recognizer expr bindings)
	      (let ((ytype (translate-to-yices* (type expr)
						bindings))
		    (yname (yices-name expr)))
		(push (format nil "(define ~a::~a)"
			yname
			ytype)
		      *ydefns*)
		yname))))))
	 

(defmethod translate-to-yices* ((expr constructor-name-expr) bindings)
  (call-next-method (lift-adt expr) bindings))


(defmethod translate-to-yices* ((expr number-expr) bindings)
      (number expr))

(defmethod translate-to-yices* ((ex string-expr) bindings)
      (string->int (string-value ex)))

(defmethod translate-to-yices* ((expr record-expr) bindings)
  (format nil "(mk-record~{ ~a~})"
    (translate-to-yices* (assignments expr) bindings)))

(defmethod translate-to-yices* ((expr tuple-expr) bindings)
  (format nil "(mk-tuple ~{ ~a~})"
    (translate-to-yices* (exprs expr) bindings)))
	
(defmethod translate-to-yices* ((expr branch) bindings)
  (format nil "(if ~a ~a ~a)"
    (translate-to-yices* (condition expr) bindings)
    (translate-to-yices* (then-part expr)bindings)
    (translate-to-yices* (else-part expr)bindings)))

(defmethod translate-to-yices* ((expr cases-expr) bindings)
  (translate-to-yices* (translate-cases-to-if expr) bindings))

(defmethod translate-to-yices* ((expr projection-expr) bindings)
  (let* ((id (make-new-variable '|x| expr))
	 (yid (yices-id-name id))
	 (ytype (translate-to-yices*
		(domain (find-supertype (type expr)))
		bindings)))
  (format nil "(lambda (~a::~a) (select ~a ~a))"
    yid ytype yid (index expr))))


(defmethod translate-to-yices* ((expr projection-application) bindings)
  (let ((arg (translate-to-yices* (argument expr) bindings)))
    (format nil "(select ~a ~a)" arg (index expr))))

(defmethod translate-to-yices* ((expr field-application) bindings)
  (with-slots (id argument type) expr
    (format nil "(select ~a ~a)"
      (translate-to-yices* argument bindings)
      id)))

    ;;NSH(5.17.94): Complicated code to deal with tuple mismatch
    ;;between domain of operator and arguments.
    ;; op(a1,..., an) if dom(type(op)) = [t1,...,tn] ==>
    ;;                      (op' (tupcons a1' .. an'))
    ;; op(a1), if dom(type(op)) = t1,...,tn ==> (op (tupsel 0 a1)...)

(defmethod translate-to-yices* ((expr application) bindings)
  (with-slots (operator argument) expr
    (let* ((op* (operator* expr))
	   (op-id (when (name-expr? op*) (id op*))))
      (cond ((and (eq op-id 'rem)
		  (eq (id (module-instance (resolution op*)))
		      'modulo_arithmetic))
	     (let ((denom (translate-to-yices* (args1 (operator expr))
					       bindings))
		   (numer (translate-to-yices* (args1 expr)
					       bindings)))
	       `(mod ,numer ,denom)))
	    ((and (eq op-id 'nat2bv)
		  (number-expr? (expr (car (actuals op*)))))
	     (let ((size (translate-to-yices*
			  (expr (car (actuals op*)))
			  bindings))
		   (num (translate-to-yices*
			 (args1 expr) bindings)))
	       `(mk-bv ,size ,num)))
	    ((and (eq op-id '-)
		  (eq (id (module-instance (resolution op*)))
		      'bv_arithmetic)
		  (not (tupletype? (domain (type op*)))))
	     (format nil "(bv-neg ~a)"
	       (translate-to-yices* (argument expr) bindings)))
	    ((and (enum-adt? (find-supertype (type argument)))
		  (recognizer? operator))
	     (format nil "(= ~a ~a)"
	       (translate-to-yices* argument bindings)
	       (translate-to-yices* (constructor operator) bindings)))
	    ((constructor? operator)
	     (format nil "(~a ~{ ~a~})"
		     (translate-to-yices* operator bindings)
		     (translate-to-yices* (arguments expr) bindings)))
	    (t
	     (let ((yices-interpretation
		    (yices-interpretation operator)))
	       (if yices-interpretation
		   (format nil "(~a ~{ ~a~})"
		     yices-interpretation
		     (translate-to-yices* (arguments expr) bindings))
		   (let ((yices-op (translate-to-yices* operator bindings))
			 (arg (translate-to-yices* (argument expr)
						   bindings)))
		     (format nil "(~a ~a)" yices-op arg)))))))))


(defun translate-yices-bindings (bind-decls bindings prefix-string)
      (cond ((consp bind-decls)
	     (let ((yname (yices-name (car bind-decls)))
		   (ytype (translate-to-yices* (type (car bind-decls)) bindings)))
	       (translate-yices-bindings (cdr bind-decls)
					 (cons (cons (car bind-decls)
						     yname)
					       bindings)
					 (format nil "~a ~a::~a"
					   prefix-string yname ytype))))
	    (t (values bindings prefix-string))))


(defmethod translate-to-yices* ((expr binding-expr) bindings)
  (with-slots ((expr-bindings bindings) expression) expr
    (multiple-value-bind (newbindings bindstring)
	(translate-yices-bindings  expr-bindings bindings "")
      (let ((yexpression (translate-to-yices* expression newbindings)))
	(cond ((lambda-expr? expr)
	       (if (singleton? expr-bindings)
		   (format nil "(lambda (~a) ~a)"
		     bindstring yexpression)
		   (let* ((lamvar (yices-id-name "lamvar"))
			  (let-list
			  (loop for bnd in expr-bindings
				as index from 1
				collect
				(format nil "(~a (select ~a ~a))"
				  (cdr (assoc bnd newbindings))
				  lamvar index))))
		     (format nil "(lambda (~a::~a)(let ~a ~a)"
		       lamvar (translate-to-yices* (domain (type expr))
						   bindings)
		       let-list (translate-to-yices* expression newbindings)))))
	      ((forall-expr? expr)
	       (format nil "(forall (~a) ~a)"
		 bindstring yexpression))
	      ((exists-expr? expr)
	       (format nil "(exists (~a) ~a)"
		 bindstring yexpression))))))) ;;no else case



;;; Update expressions
;;; Translate expressions of the form
;;; A WITH [ (0) := 1 ],
;;;    where A is an array of type int->int, into
;;; (apply int ARRAYSTORE A 0 1)
;;;
;;; f WITH [ (0,0) := 0],
;;;    where f is a function of type int,int->int into
;;; (APPLY int UPDATE f (0 0) 0)
;;;
;;; g WITH [ (0) := h, (1) (x,y) := 0, (1) (x,y)' := 1 ]
;;;    where g and h are functions of type
;;;    T = [function[int -> function[state[T0],state[T0] -> int]]
;;;
;;; This generates the form
;;;
;;; (apply function[state[T0],state[T0] -> int]
;;;        update
;;;        (apply function[state[T0],state[T0] -> int]
;;;               update
;;;               (apply function[state[T0],state[T0] -> int]
;;;                      update
;;;                      g (0) h)
;;;               (1) (apply int update g(1) (x y) 0))
;;;        (1) (apply int update g(1) (x' y') 1))

(defmethod translate-to-yices* ((expr update-expr) bindings)
  (translate-yices-assignments (assignments expr)
			       (translate-to-yices* (expression expr) bindings)
			       (type expr)
			       bindings))

(defun translate-yices-assignments (assigns 
				    trbasis type bindings)
  (if assigns
      (translate-yices-assignments
       (cdr assigns)
					;basis
       (translate-yices-assignment (car assigns) ;basis
				   trbasis type bindings)
       type
       bindings)
      trbasis))

(defun translate-yices-assignment (assign trbasis type bindings)
  (translate-yices-assign-args (arguments assign)
			       (expression assign)
			       trbasis
			       (find-supertype type)
			       bindings))

(defmethod translate-yices-assign-args (args value trbasis (type recordtype)
					     bindings)
  (if args
      (let* ((label (id (caar args)))
	     (newtrbasis (format nil "(select ~a ~a)" trbasis label)))
	(format nil "(update ~a ~a ~a)" trbasis label
		(translate-yices-assign-args
		 (cdr args) value newtrbasis
		 (type (find (id (caar args)) (fields type)
			     :test #'eq :key #'id))
		 bindings)))
      (translate-to-yices* value bindings)))

(defmethod translate-yices-assign-args (args value trbasis (type tupletype)
					     bindings)
  (if args
      (let* ((index (number (caar args)))
	     (newtrbasis (format nil "(~a ~{~a~})" trbasis index)) )
	(format nil "(update ~a (~a) ~a)" trbasis index
		(translate-yices-assign-args
		 (cdr args) value newtrbasis
		 (type (nth (1- index) (types type))) bindings)))
      (translate-to-yices* value bindings)))

(defmethod translate-yices-assign-args (args value trbasis (type funtype)
					     bindings)
  (if args
      (let* ((yargs1 (translate-to-yices* (car args) bindings))
	     (newtrbasis (format nil "(~a ~a)" trbasis yargs1)) )
	(format nil "(update ~a ~a ~a)" trbasis yargs1
		(translate-yices-assign-args
		 (cdr args) value newtrbasis
		 (range type) bindings)))
      (translate-to-yices* value bindings)))

(defmethod translate-yices-assign-args (args value trbasis (type t) bindings)
  (translate-to-yices* value bindings))

(defun yices-interpretation (name-expr)
  (when (name-expr? name-expr)
    (let* ((id-assoc (cdr (assoc (id name-expr) *yices-interpreted-names*)))
	   (mod-assoc (cdr (assoc (id (module-instance
				       (resolution name-expr)))
				  id-assoc))))
      (if (eq (id name-expr) '-)
	  (and (tupletype? (find-supertype (domain (type name-expr))))
	       mod-assoc)
	  mod-assoc))))


	




;; (defparameter *interpreted-alist*
;;   (mapcar #'(lambda (x) (cons (id x) x)) *interpreted-names*))

;; (defun interpretation (name)
;;   (or (cdr (assoc (id name) *interpretations*))
;;       (id name)))

;; (defparameter *yices-interpretations*
;;   '((= . =)
;;     (/= . /=)
;;     (< . <)
;;     (<= . <=)
;;     (> . >)
;;     (>= . >=)
;;     (+ . +)
;;     (- . -)
;;     (* . *)
;;     (/ . /)
;;     (AND . and)
;;     (OR . or)
;;     (NOT . not)
;;     (IMPLIES . =>)
;;     ( . bv-concat)
;;     ( . bv-extract)
;;     ( . bv-and)
;;     ( . bv-or)
;;     ( . bv-xor)
;;     ( . bv-not)
;;     ( . bv-left-shift0)
;;     ( . bv-left-shift1)
;;     ( . bv-right-shift0)
;;     ( . bv-right-shift1)
;;     ( . bv-sign-extend)
;;     ( . bv-add)
;;     ( . bv-sub)
;;     ( . bv-mul)
;;     ( . bv-neg)
;;     ( . bv-lt)
;;     ( . bv-le)
;;     ( . bv-gt)
;;     ( . bv-ge)
;;     ( . bv-slt)
;;     ( . bv-sle)
;;     ( . bv-sgt)
;;     ( . bv-sge)))

(defun yices (sformnums)
  #'(lambda (ps)
      (let* ((goalsequent (current-goal ps))
	     (s-forms (s-forms goalsequent))
	     (*ydefns* nil))
	(clear-yices)
	(let ((yices-forms
	       (loop for sf in s-forms
		     collect
		     (let ((fmla (formula sf)))
		       (if (negation? fmla)
			   (format nil "(assert ~a)"
			     (translate-to-yices* (args1 fmla) nil))
			   (format nil "(assert (not ~a))"
			     (translate-to-yices* fmla  nil))))))
	       (revdefns (nreverse *ydefns*))
	       (file (make-pathname :defaults (working-directory)
			     :name (label ps) :type "yices")))
	  (format t "~%ydefns = ~% ~{~a~%~}" revdefns)
	  (format t "~%yforms = ~% ~{~a~%~}" yices-forms)
	  (with-open-file (stream  file :direction :output
				    :if-exists :supersede)
	    (format stream "~{~a ~%~}" revdefns)
	    (format stream "~{~a ~%~}" yices-forms)
	    (format stream "(check)~%")
	    (format stream "(status)"))
	  (let ((status nil)
		(tmp-file (funcall *pvs-tmp-file*)))
	    (with-open-file (out tmp-file
			 :direction :output :if-exists :supersede)
	      (setq status (excl:run-shell-command
			    (format nil "~a ~a" *yices-call* (namestring file))
			    :input "//dev//null"
			    :output out
			    :error-output :output)))
	    (let ((result   (file-contents tmp-file)))
	      ;;(break "yices result")
	      (delete-file tmp-file)
;	      (delete-file file)
	      (format t "~%Result = ~a" result)
	      (cond ((search "unsat"  result :from-end t)
		     (format t "~%Yices translation of negation is unsatisfiable")
		     (values '! nil nil))
		    (t (format t "~%Yices translation of negation is not known to be satisfiable or unsatisfiable")
		       (values 'X nil nil)))))))))

	
(addrule 'yices ()
	 ((fnums *))
  (yices fnums)
  "Invokes Yices as an endgame SMT solver to prove that the conjunction
of the negations of the selected formulas is unsatisfiable. "
  "~%Simplifying with Yices,")
  