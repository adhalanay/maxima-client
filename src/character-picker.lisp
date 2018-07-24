(in-package :maxima-client)

(defparameter *char-list* '(("alpha" "α")
                            ("Alpha" "Α")
                            ("beta" "β")
                            ("Beta" "Β")
                            ("gamma" "γ")
                            ("Gamma" "Γ")
                            ("delta" "δ")
                            ("Delta" "Δ")
                            ("epsilon" "ε")
                            ("Epsilon" "Ε")
                            ("zeta" "ζ")
                            ("Zeta" "Ζ")
                            ("eta" "η")
                            ("Eta" "Η")
                            ("theta" "θ")
                            ("Theta" "Θ")
                            ("iota" "ι")
                            ("Iota" "Ι")
                            ("kappa" "κ")
                            ("Kappa" "Κ")
                            ("lambda" "λ")
                            ("Lambda" "Λ")
                            ("mu" "μ")
                            ("Mu" "Μ")
                            ("nu" "ν")
                            ("Nu" "Ν")
                            ("xi" "ξ")
                            ("Xi" "Ξ")
                            ("omicron" "ο")
                            ("Omicron" "Ο")
                            ("pi" "π")
                            ("Pi" "Π")
                            ("rho" "ρ")
                            ("Rho" "Ρ")
                            ("sigma" "σ")
                            ("Sigma" "Σ")
                            ("tau" "τ")
                            ("Tau" "Τ")
                            ("upsilon" "υ")
                            ("Upsilon" "Υ")
                            ("phi" "φ")
                            ("Phi" "Φ")
                            ("chi" "χ")
                            ("Chi" "Χ")
                            ("psi" "ψ")
                            ("Psi" "Ψ")
                            ("omega" "ω")
                            ("Omega" "Ω")))

(defclass char-popup-element ()
  ((char        :initarg :char
                :reader char-popup-element/char)
   (description :initarg :description
                :reader char-popup-element/description)))

(defmethod maxima-client.gui-tools:render-element ((value char-popup-element) stream viewport-width)
  (clim:draw-text* stream (char-popup-element/char value) 2 0 :ink clim:+black+)
  (clim:draw-text* stream (char-popup-element/description value) 40 0 :ink clim:+black+))

(defmethod maxima-client.gui-tools:get-element-filter-name ((value char-popup-element))
  (char-popup-element/description value))


(clim:define-command (select-char :name "Select character" :command-table maxima-table)
    ()
  "Display the character picker"
  (let ((values (mapcar (lambda (v)
                          (make-instance 'char-popup-element :char (second v) :description (first v)))
                        *char-list*)))
    (let ((result (maxima-client.gui-tools:select-completion-match values)))
      (when result
        (let ((point (drei:point)))
          (drei-buffer:insert-sequence point (char-popup-element/char result)))))))