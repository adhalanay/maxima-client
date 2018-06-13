(in-package :maxima-client)

(clim:define-command-table maxima-commands)

(defclass maxima-interactor-pane (clim:interactor-pane)
  ())

(clim:define-application-frame maxima-main-frame ()
  ()
  (:panes (text-content (clim:make-clim-stream-pane :type 'maxima-interactor-pane
                                                    :name 'maxima-interactor
                                                    :default-view +listener-view+
                                                    :incremental-redisplay t)))
  (:menu-bar maxima-menubar-command-table)
  (:top-level (clim:default-frame-top-level :prompt 'print-listener-prompt))
  (:command-table (maxima-main-frame :inherit-from (maxima-commands)))
  (:layouts (default (clim:vertically ()
                       text-content))))

(defgeneric presentation-pointer-motion (presentation x y)
  (:method (presentation x y)
    nil))

(defmethod clim-internals::frame-input-context-track-pointer ((frame maxima-main-frame)
                                                              input-context
                                                              stream
                                                              event)
  (let* ((x (clim-internals::device-event-x event))
         (y (clim-internals::device-event-y event))
         (presentation (find-presentation-at-pos x y)))
    (when presentation
      (presentation-pointer-motion presentation x y)))
  (call-next-method))

(defclass labelled-expression ()
  ((tag :initarg :tag
          :reader labelled-expression/tag)
   (expr  :initarg :expr
          :reader labelled-expression/expr)))

(clim:define-presentation-method clim:present (obj (type labelled-expression) stream (view t) &key)
  (let* ((name (format-sym-name (labelled-expression/tag obj)))
         (s (if (and (plusp (length name))
                     (eql (aref name 0) #\$))
                (subseq name 1)
                name)))
    (clim:formatting-table (stream)
      (clim:formatting-row (stream)
        (clim:formatting-cell (stream :align-y :center :min-width 75)
          (format stream "(~a)" s))
        (clim:formatting-cell (stream :align-y :center)
          (present-to-stream (labelled-expression/expr obj) stream))))))

(clim:define-presentation-type plain-text ()
  :inherit-from 'string)

(clim:define-presentation-type maxima-empty-input ())

(clim:define-presentation-type maxima-native-expr
    ()
  :inherit-from t)

(clim:define-presentation-type maxima-lisp-package-form
    ()
  :inherit-from 'clim:form)

(clim:define-presentation-method clim:present (obj (type plain-text) stream (view clim:textual-view) &key)
  (log:info "STD TEXT present: ~s" obj)
  (format stream "~a" obj))

(clim:define-presentation-method clim:present (obj (type plain-text) (stream string-stream) (view t) &key)
  (log:info "STR TEXT present: ~s" obj)
  (format stream "~a" obj))

(defun read-plain-text (stream
                        &key
                          (input-wait-handler clim:*input-wait-handler*)
		          (pointer-button-press-handler clim:*pointer-button-press-handler*)
		          click-only)
  (declare (ignore click-only))
  (let ((result (make-array 1 :adjustable t :fill-pointer 0 :element-type 'character)))
    (loop
      for first-char = t then nil
      for gesture = (clim:read-gesture :stream stream
		                       :input-wait-handler input-wait-handler
		                       :pointer-button-press-handler pointer-button-press-handler)
      do (cond ((or (null gesture)
		    (clim:activation-gesture-p gesture)
		    (typep gesture 'clim:pointer-button-event)
		    (clim:delimiter-gesture-p gesture))
		(loop-finish))
	       ((characterp gesture)
		(vector-push-extend gesture result))
	       (t nil))
      finally (progn
		(when gesture
		  (clim:unread-gesture gesture :stream stream))
		(return (subseq result 0))))))

(clim:define-presentation-method clim:accept ((type plain-text)
                                              stream (view clim:textual-view)
                                              &key
                                              (default nil defaultp)
                                              (default-type type))
  (let ((result (read-plain-text stream)))
    (log:trace "Got string from reading plain-text: ~s" result)
    (cond ((and (equal result "") defaultp)
           (values default default-type))
          (t (values result type)))))

(defmethod clim:presentation-replace-input ((stream drei:drei-input-editing-mixin) (obj maxima-native-expr) type view
                                            &key (buffer-start nil buffer-start-p) (rescan nil rescan-p)
                                              query-identifier
                                              for-context-type)
  #+nil  (declare (ignore query-identifier for-context-type))
  (log:info "Replacing input for ~s, bs=~s, bs-p=~s, rescan=~s, rsp=~s, qi=~s fct=~s"
            obj buffer-start buffer-start-p rescan rescan-p query-identifier for-context-type)
  (apply #'clim:presentation-replace-input stream (maxima-native-expr/src obj) 'plain-text view
         (append (if buffer-start-p (list :buffer-start buffer-start) nil)
                 (if rescan-p (list :rescan rescan) nil))))

(clim:define-presentation-method clim:accept
    ((type maxima-native-expr)
     (stream drei:drei-input-editing-mixin)
     (view clim:textual-view)
     &key)
  (let ((clim:*completion-gestures* nil)
        (clim:*possibilities-gestures* nil))
    (clim:with-delimiter-gestures (nil :override t)
      (loop
        named control-loop
        with drei = (drei:drei-instance stream)
        ;;with syntax = (drei:syntax (clim:view drei))
        ;; The input context permits the user to mouse-select displayed
        ;; Lisp objects and put them into the input buffer as literal
        ;; objects.
        for gesture = (clim:with-input-context ('maxima-native-expr :override nil)
                          (object type)
                          (clim:read-gesture :stream stream)
                        (maxima-native-expr (drei:performing-drei-operations (drei :with-undo t
                                                                                   :redisplay t)
                                              (clim:presentation-replace-input
                                               stream object type (clim:view drei)
                                               :buffer-start (clim:stream-insertion-pointer stream)
                                               :allow-other-keys t
                                               :accept-result nil
                                               :rescan t))
                                            (clim:rescan-if-necessary stream)
                                            nil))
        ;; True if `gesture' was freshly read from the user, and not
        ;; just retrieved from the buffer during a rescan.
        for freshly-inserted = (and (plusp (clim:stream-scan-pointer stream))
                                    (not (equal (drei::buffer-object
                                                 (drei:buffer (clim:view drei))
                                                 (1- (clim:stream-scan-pointer stream)))
                                                gesture)))
        ;;for form = (drei-lisp-syntax::form-after syntax (drei::input-position stream))
        ;; We do not stop until the input is complete and an activation
        ;; gesture has just been provided. The freshness check is so
        ;; #\Newline characters in the input will not cause premature
        ;; activation.
        until (and (clim:activation-gesture-p gesture)
                   (and freshly-inserted
                        (let ((gesture-event (climi::last-gesture (clim::encapsulating-stream-stream stream))))
                          (and (typep gesture-event 'clim:keyboard-event)
                               (zerop (logand (clim::event-modifier-state gesture-event) #x100))))))
             ;; We only want to process the gesture if it is fresh,
             ;; because if it isn't, it has already been processed at
             ;; some point in the past.
        when (and (clim:activation-gesture-p gesture)
                  freshly-inserted)
          do (progn
               (clim:with-activation-gestures (nil :override t)
                 (clim:stream-process-gesture stream gesture nil)))
        finally 
           (progn
             (clim:unread-gesture gesture :stream stream)
             (let* ((object (handler-case
                                (let* ((buffer (drei:buffer (clim:view drei)))
                                       (start (drei::input-position stream))
                                       (end (drei::size buffer)))
                                  (string-to-native-expr (drei::buffer-substring buffer start end)))
                              (maxima-expr-parse-error (condition)
                                ;; Move point to the problematic form
                                ;; and signal a rescan.
                                (setf (drei::activation-gesture stream) nil)
                                (drei:handle-drei-condition drei condition)
                                (drei:display-drei drei :redisplay-minibuffer t)
                                (clim:immediate-rescan stream))))
                    (ptype (clim:presentation-type-of object)))
               (return-from control-loop
                 (values object
                         (if (clim:presentation-subtypep ptype 'maxima-native-expr)
                             ptype 'maxima-native-expr)))))))))

#+nil
(clim:define-presentation-method clim:accept ((type maxima-native-expr)
                                              stream (view clim:textual-view)
                                              &key
                                              (default nil defaultp)
                                              (default-type type))
  (let ((s (read-plain-text stream)))
    (log:trace "Got string from reading native expr: ~s" s)
    (let ((trimmed (string-trim " " s)))
      (if (equal trimmed "")
          (if defaultp
              (values default default-type)
              (values nil 'maxima-empty-input))
          (values (string-to-native-expr trimmed) type)))))

(clim:define-presentation-method clim:accept ((type maxima-lisp-package-form)
                                              stream
                                              (view clim:textual-view)
                                              &key)
  (with-maxima-package
    (clim:accept 'clim:form :stream stream :view view :prompt nil)))

(clim:define-presentation-type maxima-expression-or-command
    (&key (command-table (clim:frame-command-table clim:*application-frame*)))
  :inherit-from t)

(clim:define-presentation-method clim:accept ((type maxima-expression-or-command)
                                              stream
				              (view clim:textual-view)
				              &key)
  (let ((command-ptype `(clim:command :command-table ,command-table)))
    (clim:with-input-context (`(or ,command-ptype maxima-native-expr))
        (object type event options)
        (let ((initial-char (clim:read-gesture :stream stream :peek-p t)))
	  (if (member initial-char clim:*command-dispatchers*)
	      (progn
		(clim:read-gesture :stream stream)
		(clim:accept command-ptype :stream stream :view view :prompt nil :history 'clim:command))
	      (clim:accept 'maxima-native-expr :stream stream :view view :prompt nil
                                               :history 'maxima-expression-or-command :replace-input t)))
      (t
       (funcall (cdar clim:*input-context*) object type event options)))))

(clim:define-presentation-translator maxima-to-plain-text (maxima-native-expr plain-text maxima-commands)
    (object)
  (log:trace "Converting to text: ~s" object)
  (maxima-native-expr/src object))

(clim:define-presentation-translator plain-text-to-maxima (plain-text maxima-native-expr maxima-commands)
    (object)
  (log:trace "Converting to maxima expr: ~s" object)
  (string-to-native-expr object))

(defmethod clim:read-frame-command ((frame maxima-main-frame) &key (stream *standard-input*))
  (handler-case
      (multiple-value-bind (object type)
          (let ((clim:*command-dispatchers* '(#\:))
                (clim:*command-unparser* (lambda (command-table stream command)
                                           (log:info "unparsing ~s (~s ~s)" command command-table stream))))
            (clim:with-text-style (stream (clim:make-text-style :fix :roman :normal))
              (clim:accept 'maxima-expression-or-command :stream stream :prompt nil
                                                         :default nil :default-type 'maxima-empty-input
                                                         :history 'maxima-expression-or-command
                                                         :replace-input t)))
        (log:trace "Got input: object=~s, type=~s" object type)
        (cond
          ((null object)
           nil)
          ((eq type 'maxima-native-expr)
           `(maxima-eval ,object))
          ((and (listp type) (eq (car type) 'clim:command))
           object)))
    (maxima-native-error (condition)
      (render-error-message stream (format nil "~a" condition))
      nil)))

(defmethod clim:stream-present :around ((stream maxima-interactor-pane) object type
                                   &rest args
                                   &key (single-box nil single-box-p) &allow-other-keys)
  (declare (ignore single-box single-box-p))
  (apply #'call-next-method stream object type :single-box t args))

(defun print-listener-prompt (stream frame)
  (declare (ignore frame))
  ;; It would be more logical to put this in the ACCEPT method, but by
  ;; then the prompt has already been printed, so we'll update it here
  ;; instead.
  (when (or (not (maxima::checklabel maxima::$inchar))
	    (not (maxima::checklabel maxima::$outchar)))
    (incf maxima::$linenum))
  (format stream "~a " (maxima::main-prompt)))

(defun maxima-client ()
  (let ((fonts-location (merge-pathnames #p"fonts/tex/" (asdf:component-pathname (asdf:find-system :maxima-client)))))
    (mcclim-fontconfig:app-font-add-dir fonts-location))
  (with-maxima-package
    (maxima::initialize-runtime-globals))
  (setq *debugger-hook* nil)
  ;; Set up default plot options
  (setf (getf maxima::*plot-options* :plot_format) 'maxima::$clim)
  ;;
  (let ((frame (clim:make-application-frame 'maxima-main-frame
                                            :width 900
                                            :height 600)))
    (clim:run-frame-top-level frame)))

(clim:define-command (maxima-eval :name "Eval expression" :menu t :command-table maxima-commands)
    ((cmd 'maxima-native-expr :prompt "expression"))
  (let ((c-tag (maxima::makelabel maxima::$inchar)))
    (setf (symbol-value c-tag) (maxima-native-expr/expr cmd))
    (let* ((maxima-stream (make-instance 'maxima-io :clim-stream *standard-output*))
           (eval-ret (catch 'maxima::macsyma-quit
                       (let ((result (let ((*use-clim-retrieve* t)
                                           (*current-stream* *standard-output*)
                                           (*standard-output* maxima-stream)
                                           (*standard-input* maxima-stream))
                                       (eval-maxima-expression (maxima-native-expr/expr cmd)))))
                         (log:debug "Result: ~s" result)
                         (let ((d-tag (maxima::makelabel maxima::$outchar)))
                           (setf (symbol-value d-tag) result)
                           (let ((obj (make-instance 'maxima-native-expr :expr result)))
                             (clim:with-room-for-graphics (*standard-output* :first-quadrant nil)
                               (clim:surrounding-output-with-border (*standard-output* :padding 10 :ink clim:+transparent-ink+)
                                 (present-to-stream (make-instance 'labelled-expression
                                                                   :tag d-tag
                                                                   :expr obj)
                                                    *standard-output*)))))))))
      (let ((content (maxima-stream-text maxima-stream)))
        (cond ((eq eval-ret 'maxima::maxima-error)
               (present-to-stream (make-instance 'maxima-error
                                                 :cmd cmd
                                                 :content content)
                                  *standard-output*))
              (t
               (when (plusp (length content))
                 (log:info "Output from command: ~s" content))))))))

(clim:define-command (maxima-quit :name "Quit" :menu t :command-table maxima-commands)
    ()
  (clim:frame-exit clim:*application-frame*))

(clim:define-command (maxima-eval-lisp-expression :name "Lisp" :menu "Eval Lisp form" :command-table maxima-commands)
    ((form maxima-lisp-package-form :prompt "Form"))
  (let ((result (with-maxima-package
                  (maxima::eval form))))
    #+nil
    (present-to-stream result *standard-output* :record-type 'clim:form)
    (clim:with-output-as-presentation (*standard-output* result (clim:presentation-type-of result) :single-box t)
      (clim:present result 'clim:expression :stream *standard-output*))))

(clim:make-command-table 'maxima-menubar-command-table
                         :errorp nil
                         :menu '(("File" :menu maxima-file-command-table)
                                 ("Plot" :menu maxima-plot-command-table)
                                 ("Lisp" :menu maxima-lisp-command-table)))

(clim:make-command-table 'maxima-file-command-table
                         :errorp nil
                         :menu '(("Quit" :command maxima-quit)))

(clim:make-command-table 'maxima-plot-command-table
                         :errorp nil
                         :menu '(("Discrete" :command plot2d-with-range)
                                 ("Parametric" :command plot2d-with-range)
                                 ("Plot examle" :command plot2d-demo)))

(clim:make-command-table 'maxima-lisp-command-table
                         :errorp nil
                         :menu '(("Eval Lisp Form" :command maxima-eval-lisp-expression)))
