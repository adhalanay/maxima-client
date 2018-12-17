(in-package :maxima-client)

(defvar *aligned-rendering-pos*)
(defvar *aligned-rendering-stream*)
(defvar *font-size*)

(clim:define-presentation-type plain-text ()
  :inherit-from 'string)

(clim:define-presentation-type maxima-native-expr
    ()
  :inherit-from t)

(clim:define-presentation-type maxima-native-symbol
    ()
  :inherit-from t)

(defun %aligned-render-and-move (stream pos fn)
  (let ((output-record (clim:with-output-to-output-record (stream)
                         (funcall fn))))
    (move-rec output-record pos 0)
    (clim:stream-add-output-record stream output-record)
    (dimension-bind (output-record :right right)
      right)))

(defmacro with-aligned-rendering ((stream) &body body)
  `(let ((*aligned-rendering-pos* 0)
         (*aligned-rendering-stream* ,stream))
     ,@body))

(defmacro render-aligned (() &body body)
  `(setf *aligned-rendering-pos* (%aligned-render-and-move *aligned-rendering-stream* *aligned-rendering-pos*
                                                           (lambda () ,@body))))

(defun aligned-spacing (spacing)
  (incf *aligned-rendering-pos* (* (char-width *aligned-rendering-stream*) spacing)))

(defun render-aligned-string (fmt &rest args)
  (render-aligned ()
    (clim:draw-text* *aligned-rendering-stream* (apply #'format nil fmt args) 0 0)))

(defun render-formatted (stream fmt &rest args)
  (with-aligned-rendering (stream)
    (apply #'render-aligned-string fmt args)))

(defun char-height (stream)
  (multiple-value-bind (width height)
      (clim:text-size stream "M")
    (declare (ignore width))
    height))

(defun char-width (stream)
  (multiple-value-bind (width height)
      (clim:text-size stream "M")
    (declare (ignore height))
    width))

(defclass single-dimension-text-rec (clim:standard-rectangle clim:output-record)
  ((parent :initarg :parent
           :initform nil
           :accessor clim:output-record-parent)
   (rec :initform nil
        :accessor single-dimension-text-rec/output-record)))

(defmethod clim:add-output-record (child (parent single-dimension-text-rec))
  (when (single-dimension-text-rec/output-record parent)
    (error "single-dimension-text-rec can only have a single child"))
  (setf (single-dimension-text-rec/output-record parent) child))

(defmethod clim:replay-output-record ((record single-dimension-text-rec) stream &optional region x-offset y-offset)
  (let ((inner (single-dimension-text-rec/output-record record)))
    (unless inner
      (error "single-dimension-text-rec does not contain a child record"))
    (clim:replay-output-record inner stream region x-offset y-offset)))

(defmethod clim:bounding-rectangle* ((rec single-dimension-text-rec))
  (clim:rectangle-edges* rec))

(defmethod clim:output-record-position ((rec single-dimension-text-rec))
  (multiple-value-bind (x y)
      (clim:bounding-rectangle* rec)
    (values x y)))

(defun text-style-font-ascent (stream)
  (climb:text-style-ascent (clim:medium-text-style stream) stream))

(defun text-style-font-descent (stream)
  (climb:text-style-descent (clim:medium-text-style stream) stream))

(defun text-style-font-height (stream)
  (let ((style (clim:medium-text-style stream)))
    (+ (climb:text-style-ascent style stream)
       (climb:text-style-descent style stream))))

(defun render-symbol-str (stream string)
  (let ((rec (clim:with-output-to-output-record (stream)
               (clim:draw-text* stream string 0 0))))
    #+nil
    (multiple-value-bind (x1 y1 x2 y2)
        (clim:bounding-rectangle* rec)
      (let* ((font-ascent (text-style-font-ascent)))
        (log:info "ascent = ~s" font-ascent)
        (when (< font-ascent y1)
          (setf (clim:rectangle-edges* rec) (values x1 font-ascent x2 y2))))
      (clim:stream-add-output-record stream rec))
    (clim:stream-add-output-record stream rec)))

(defun find-replacement-text-styles (stream string &key text-style)
  (clim:with-sheet-medium (medium stream)
    (clim-freetype::find-replacement-fonts (clim:port medium) (or text-style (clim:medium-text-style stream)) string)))

(defun render-formatted-with-replacement (stream fmt &rest args)
  (with-aligned-rendering (stream)
    (let ((blocks (find-replacement-text-styles stream (apply #'format nil fmt args)))
          (font-size (clim:text-style-size (clim:medium-text-style stream))))
      (log:trace "blocks: ~s" blocks)
      (loop
        for (string family style) in blocks
        if family
          do (clim:with-text-style (stream (clim:make-text-style family style font-size))
               (render-aligned () (render-symbol-str stream string)))
        else
          do (render-aligned () (render-symbol-str stream string))))))
