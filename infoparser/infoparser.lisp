(in-package :infoparser)

(defun %markup-from-regexp (regexp string callback &optional plain-string-markup-fn)
  (flet ((markup-string (s)
           (if plain-string-markup-fn
               (funcall plain-string-markup-fn s)
               (list s))))
    (loop
      with length = (length string)
      with start = 0
      while (< start length)
      append (multiple-value-bind (match-start match-end reg-starts reg-ends)
                 (cl-ppcre:scan regexp string :start start)
               (if match-start
                   ;; Some highlighted text was found
                   (let* ((highlight (funcall callback reg-starts reg-ends))
                          (old-start start))
                     (setq start match-end)
                     (if (> match-start old-start)
                         ;; There is some unmatched text before the match
                         (append (markup-string (subseq string old-start match-start))
                                 (list highlight))
                         ;; ELSE: The match is at the beginning of the string
                         (list highlight)))
                   ;; ELSE: No match, copy the last part of the text and finish the loop
                   (progn
                     (let ((old-start start))
                       (setq start length)
                       (markup-string (subseq string old-start)))))))))

(defmacro markup-from-regexp (regexp string callback &optional plain-string-markup-fn &environment env)
  `(%markup-from-regexp ,(if (constantp regexp env) `(load-time-value (cl-ppcre:create-scanner ,regexp)) regexp)
                        ,string ,callback ,@(if plain-string-markup-fn (list plain-string-markup-fn))))

(defun %iterate-regexps (regexp string callback)
  (loop
    with length = (length string)
    with start = 0
    while (< start length)
    do (multiple-value-bind (match-start match-end reg-starts reg-ends)
           (cl-ppcre:scan regexp string :start start)
         (cond (match-start
                (setq start match-end)
                (let ((vec (make-array (length reg-starts) :element-type 'string :initial-element "")))
                  (loop
                    for start across reg-starts
                    for end across reg-ends
                    for i from 0
                    do (setf (aref vec i) (subseq string start end)))
                  (funcall callback vec)))
               (t
                (setq start length))))))

(defmacro iterate-regexps ((sym regexp string) &body body &environment env)
  `(%iterate-regexps ,(if (constantp regexp env) `(load-time-value (cl-ppcre:create-scanner ,regexp)) regexp)
                     ,string
                     (lambda (,sym) ,@body)))

(defun process-menu (stream)
  (cons :menu
        ;; Only process lines matching * title ::
        (loop
          for s = (read-line stream)
          until (cl-ppcre:scan "^@end menu *$" s)
          append (multiple-value-bind (match strings)
                     (cl-ppcre:scan-to-strings "^ *\\* *([^ ]+(?: +[^ ]+)*) *:: *$" s)
                   (if match
                       (list (aref strings 0))
                       ;; ELSE: No match
                       nil)))))

(defun parse-paragraph (s)
  (cons :paragraph
        (markup-from-regexp "@([a-z]+){([^}]+)}" s
                            (lambda (reg-starts reg-ends)
                              (let ((cmd (subseq s (aref reg-starts 0) (aref reg-ends 0)))
                                    (content (subseq s (aref reg-starts 1) (aref reg-ends 1))))
                                (list (string-case:string-case (cmd)
                                        ("code" :code)
                                        ("var" :var)
                                        ("mref" :mref)
                                        ("emph" :italic)
                                        ("i" :italic)
                                        ("strong" :bold)
                                        ("b" :bold)
                                        ("anchor" :anchor)
                                        ("xref" :xref)
                                        ("fname" :fname)
                                        ("math" :math)
                                        ("mrefcomma" :mrefcomma)
                                        ("mrefdot" :mrefdot)
                                        ("ref" :ref)
                                        ("mxrefcomma" :mxrefcomma) ;; 2-arg
                                        ("mxref" :mxref) ;; 2-arg
                                        ("mxrefdot" :mxrefdot) ;; 2-arg
                                        ("file" :file)
                                        ("mrefparen" :mrefparen)
                                        ("footnote" :footnote)
                                        ("kbd" :kbd)
                                        ("key" :key) ;; Same as kbd?
                                        ("image" :image) ;; filename,size
                                        ("dfn" :dfn)
                                        ("url" :url)
                                        ("uref" :url)
                                        ("figure" :figure)
                                        ("verb" :verb)
                                        ("dotless" :dotless) ;; Only used to create a dotless i
                                        ("email" :email)
                                        ("pxref" :pxref)
                                        (t (error "Unknown cmd: ~s" cmd)))
                                      content)))
                            (lambda (s)
                              (list (cl-ppcre:regex-replace-all "@dots{}" s "…"))))))

(defun process-opencatbox (stream)
  (cons :catbox
        (loop
          for s = (read-line stream)
          until (cl-ppcre:scan "^@closecatbox *$" s)
          append (collectors:with-collector (coll)
                   (iterate-regexps (category "@category{([^}]+)}" s)
                     (coll (aref category 0)))
                   (coll)))))

(defun parse-node (args)
  (labels ((nil-or-trim (s)
             (if s
                 (let ((trimmed (string-trim " " s)))
                   (if (zerop (length trimmed)) nil trimmed))
                 nil)))
    (let* ((category-names (split-sequence:split-sequence #\, args))
           (name (string-trim " " (nth 0 category-names)))
           (next (nil-or-trim (nth 1 category-names)))
           (prev (nil-or-trim (nth 2 category-names)))
           (up (nil-or-trim (nth 3 category-names))))
      (list :node name next prev up))))

(defun process-demo-code (stream)
  (let ((code (collectors:with-collector (coll)
                (loop
                  with curr = ""
                  for s = (read-line stream)
                  until (cl-ppcre:scan "^@c ===end===" s)
                  unless (zerop (length s))
                    do (multiple-value-bind (match strings)
                           (cl-ppcre:scan-to-strings "@c +(.*[^ ]) *$" s)
                         (if match
                             (setq curr (format nil "~a ~a" curr (aref strings 0)))
                             ;; ELSE: Check if this is a continuation line
                             (if (cl-ppcre:scan "^[^@]" s)
                                 (setq curr (format nil "~a ~a" curr s))
                                 (error "Demo code block does not have the expected format: ~s" s)))
                         (when (cl-ppcre:scan "(?:;|\\$) *$" curr)
                           (coll curr)
                           (setq curr ""))))
                (coll))))
    ;; After the example code, the following example group needs to be skipped
    (loop
      for s = (read-line stream)
      until (cl-ppcre:scan "^@example *$" s)
      unless (cl-ppcre:scan "^ *$" s)
        do (error "No example block following demo code"))
    (loop
      for s = (read-line stream)
      until (cl-ppcre:scan "^@end example$" s))
    (cons :demo-src code)))

(defun %skip-block (stream end-tag)
  (loop
    for s = (read-line stream)
    until (cl-ppcre:scan end-tag s)))

(defmacro skip-block (stream end-tag &environment env)
  (alexandria:once-only (stream)
    `(%skip-block ,stream
                  ,(if (constantp end-tag env)
                       `(load-time-value (cl-ppcre:create-scanner ,end-tag))
                       `(cl-ppcre:create-scanner ,end-tag)))))

(eval-when (:compile-toplevel :load-toplevel :execute)
  (defun %process-single-line-command (string clauses)
    (alexandria:with-gensyms (match parts)
      (let ((clause (car clauses)))
        `(multiple-value-bind (,match ,parts)
             (cl-ppcre:scan-to-strings ,(caar clause) ,string)
           (declare (ignorable ,parts))
           (if ,match
               ,(if (cadar clause)
                    `(let ((,(cadar clause) ,parts))
                       ,@(cdr clause))
                    `(progn ,@(cdr clause)))
               ,@(if (cdr clauses)
                     (list (%process-single-line-command string (cdr clauses)))
                     nil)))))))

(defmacro process-single-line-command (string &body clauses)
  (alexandria:once-only (string)
    (%process-single-line-command string clauses)))

(defun parse-file (file)
  (log:trace "Parsing file: ~s" file)
  (collectors:with-collector (info-collector)
    (let ((current-paragraph (make-array 0 :element-type 'character :adjustable t :fill-pointer t)))
      (labels ((collect-paragraph ()
                 (when (plusp (length current-paragraph))
                   (info-collector (parse-paragraph current-paragraph))
                   (setq current-paragraph (make-array 0 :element-type 'character :adjustable t :fill-pointer t)))))
        (with-open-file (stream file :direction :input :external-format :utf-8)
          (loop
            for s = (read-line stream nil nil)
            while s
            do (cond ((cl-ppcre:scan "^@[a-z]+(?: |$)" s)
                      (process-single-line-command s
                        (("^@c ===beg===") (info-collector (process-demo-code stream)))
                        (("^@menu *$") (info-collector (process-menu stream)))
                        (("^@opencatbox *$") (info-collector (process-opencatbox stream)))
                        (("^@node +(.*)$" args) (info-collector (parse-node (aref args 0))))
                        (("@section +(.*[^ ]) *$" name) (info-collector (list :section (aref name 0))))
                        (("^@c ") nil)
                        (("^@ifhtml *$") (skip-block stream "@end ifhtml"))
                        (("^@iftex *$") (skip-block stream "@end iftex"))))
                     ((cl-ppcre:scan "^ *$" s)
                      (collect-paragraph))
                     (t
                      ;; This is normal content, so we'll collect it into the output string
                      (when (plusp (length current-paragraph))
                        (vector-push-extend #\Space current-paragraph))
                      (loop for ch across s do (vector-push-extend ch current-paragraph))))))
        (collect-paragraph)
        (info-collector)))))

(defun evaluate-one-demo-src-line (src)
  (when (cl-ppcre:scan "^ *:" src)
    (return-from evaluate-one-demo-src-line nil))
  (let* ((expr (string-to-maxima-expr src))
         (c-tag (maxima::makelabel maxima::$inchar))
         (out (make-string-output-stream)))
    (setf (symbol-value c-tag) expr)
    (let ((eval-ret (catch 'maxima::macsyma-quit
                      (catch 'eval-expr-error
                        (let ((result (let ((*use-clim-retrieve* nil)
                                            (*standard-output* out))
                                        (handler-bind ((error (lambda (condition)
                                                                (throw 'eval-expr-error (cons :lisp-error condition)))))
                                          (eval-maxima-expression expr)))))
                          (let ((d-tag (maxima::makelabel maxima::$outchar)))
                            (setq maxima::$% result)
                            (setf (symbol-value d-tag) result)
                            (cons :result result)))))))
      (unless (and (consp eval-ret)
                   (eq (car eval-ret) :result))
        (error "Error when evaluating command: ~s: ~s" src eval-ret))
      (cdr eval-ret))))

(defun evaluate-demo-src (src)
  (eval-maxima-expression (string-to-maxima-expr "kill(all)"))
  (loop
    for v in src
    for output = (evaluate-one-demo-src-line v)
    collect (list v output)))

(defun resolve-example-code (info-content)
  (with-maxima-package
    (maxima::initialize-runtime-globals))
  (setq *debugger-hook* nil)
  (loop
    for v in info-content
    collect v
    if (eq (car v) :demo-src)
      collect (cons :demo-code (evaluate-demo-src (cdr v)))))

(defun parse-doc-directory (info-directory)
  (let ((dir (merge-pathnames "*.texi" info-directory)))
    (loop
      for file in (directory dir)
      for content = (parse-file file)
      collect (list :file file content))))
