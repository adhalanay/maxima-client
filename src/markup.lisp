(in-package :maxima-client.markup)

(clim:define-command-table text-commands)

(defclass text-link ()
  ((src :initarg :src
        :reader text-link/src)
   (description :initarg :description
                :initform nil)))

(defgeneric text-link/description (obj)
  (:method ((obj text-link))
    (or (slot-value obj 'description)
        (text-link/src obj))))

(defun make-text-link-from-markup (args)
  (cond ((alexandria:sequence-of-length-p args 1)
         (make-instance 'text-link :src (first args)))
        ((alexandria:sequence-of-length-p args 2)
         (make-instance 'text-link :src (first args) :description (second args)))
        (t
         (error "Illegally formatted text-link entry: ~s" args))))

(clim:define-presentation-method clim:present (obj (type text-link) stream (view t) &key)
  (clim:with-drawing-options (stream :ink clim:+blue+)
    (format stream "~a" (text-link/description obj))))

(clim:define-presentation-translator text-to-text-link (string text-link text-commands)
    (object)
  (make-instance 'text-link :src object))

(clim:define-presentation-to-command-translator select-url
    (text-link open-url text-commands)
    (obj)
  (list obj))

(clim:define-command (open-url :name "Open URL" :menu t :command-table text-commands)
    ((url 'text-link :prompt "URL"))
  (let ((s (text-link/src url))
        (stream (find-interactor-pane)))
    (format stream "Opening URL: ~a" s)
    (bordeaux-threads:make-thread (lambda ()
                                    (uiop/run-program:run-program (list "xdg-open" s))))))

(defun display-markup-list (stream content)
  (log:trace "displaying markup list: ~s" content)
  (loop
    for v in content
    do (display-markup stream v)))

(defun keyword->key-label (key)
  (ecase key
    (:control "Control")
    (:shift "Shift")
    (:meta "Meta")
    (:super "Super")
    (:hyper "Hyper")))

(defun call-with-key-string (stream fn)
  (let ((rec (clim:with-output-to-output-record (stream)
               (funcall fn stream))))
    (multiple-value-bind (x y)
        (clim:stream-cursor-position stream)
      (set-rec-position rec x y))
    (clim:stream-add-output-record stream rec)
    (let ((x-spacing 2))
      (dimension-bind (rec :x x :y y :right right :bottom bottom :width width)
        (clim:draw-rectangle* stream (- x x-spacing) y (+ right x-spacing) bottom :filled nil )
        (clim:stream-increment-cursor-position stream (+ width (* x-spacing 2)) 0)))))

(defmacro with-key-string ((stream) &body body)
  (check-type stream symbol)
  `(call-with-key-string ,stream (lambda (,stream) ,@body)))

(defun render-key-command (stream key-seq)
  (clim:with-text-style (stream (clim:make-text-style :fix :roman nil))
    (loop
      for group in key-seq
      do (with-key-string (stream)
           (loop
             for key in group
             for first = t then nil
             unless first
               do (format stream "-")
             do (etypecase key
                  (keyword (format stream "~a" (keyword->key-label key)))
                  (string (format stream "~a" key))))))))

(defun display-possibly-tagged-list (stream content)
  (labels ((display (v)
             (display-markup-list stream v)))
   (when (null content)
     (return-from display-possibly-tagged-list nil))
    (case (car content)
      (:heading (clim:with-text-style (stream (clim:make-text-style :sans-serif :bold :large)) (display (cdr content))))
      (:bold (clim:with-text-face (stream :bold) (display (cdr content))))
      (:code (clim:with-text-family (stream :fix) (display (cdr content))))
      (:link (maxima-client::present-to-stream (make-text-link-from-markup (cdr content)) stream))
      (:key (render-key-command stream (cdr content)))
      (:p (format stream "~&") (display (cdr content)))
      (:newline (format stream "~%"))
      (t (display-markup-list stream content)))))

(defun display-markup (stream content)
  (etypecase content
    (string (present-multiline-with-wordwrap stream content))
    (list (display-possibly-tagged-list stream content))))
