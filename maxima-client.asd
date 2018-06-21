(defsystem maxima-client
  :name "maxima-client"
  :author "Elias Martenson <lokedhs@gmail.com>"
  :license "BSD"
  :description "Maxima CLIM client"
  :depends-on (:alexandria
               :mcclim
               :log4cl
               :trivial-gray-streams
               :trivial-arguments
               :lambda-fiddle
               :cl-ppcre
               :maxima)
  :components ((:module src
                        :serial t
                        :components ((:file "package")
                                     (:file "util")
                                     (:file "popup")
                                     (:file "renderer")
                                     (:file "output")
                                     (:file "queries")
                                     (:file "info")
                                     (:file "reflect")
                                     (:file "maxima-syntax")
                                     (:file "cmdline")
                                     (:file "maxima-plot")
                                     (:file "plot2d")))))
