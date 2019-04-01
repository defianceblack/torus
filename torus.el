;;; torus.el --- A buffer groups manager             -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Chimay

;; Author : Chimay
;; Name: Torus
;; Package-Version: 1.10
;; Package-requires: ((emacs "26"))
;; Keywords: files, buffers, groups, persistent, history, layout, tabs
;; URL: https://github.com/chimay/torus

;;; Commentary:

;; If you ever dreamed about creating and switching buffer groups at will
;; in Emacs, Torus is the tool you want.
;;
;; In short, this plugin let you organize your buffers by creating as
;; many buffer groups as you need, add the files you want to it and
;; quickly navigate between :
;;
;;   - Buffers of the same group
;;   - Buffer groups
;;   - Workspaces, ie sets of buffer groups
;;
;; Note that :
;;
;;   - A location is a pair (buffer (or filename) . position)
;;   - A buffer group, in fact a location group, is called a circle
;;   - A set of buffer groups is called a torus (a circle of circles)
;;
;; Original idea by Stefan Kamphausen, see https://www.skamphausen.de/cgi-bin/ska/mtorus
;;
;; See https://github.com/chimay/torus/blob/master/README.org for more details

;;; License:
;;; ----------------------------------------------------------------------

;; This file is not part of Emacs.

;; This program is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful, but
;; WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING. If not, write to the
;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;; Boston, MA 02111-1307, USA.

;;; Credits:
;;; ----------------------------------------------------------------------

;; Stefan Kamphausen, https://www.skamphausen.de/cgi-bin/ska/mtorus
;; Sebastian Freundt, https://sourceforge.net/projects/mtorus.berlios/

;;; Structure:
;;; ----------------------------------------------------------------------

;;                 lace
;;               +---+---+      +---------------------+-------------+
;;         +-----+   |   +------+ current-torus-index | lace-length |
;;         |     +---+---+      +---------------------+-------------+
;;         |
;;         |
;;    +----+----+---------+-------+---------+
;;    | torus 1 | torus 2 | ...   | torus M |
;;    +----+----+---------+-------+---------+
;;         |
;;         |
;;         |
;;     +---+---+---+       +----------------------+--------------+
;;     | torus |   +-------+ current-circle-index | torus-length |
;;     +---+---+---+       +----------------------+--------------+
;;         |
;;         |
;;         |
;; +-------+------+----------+----------+-------+----------+
;; | "torus name" | circle 1 | circle 2 | ...   | circle N |
;; +--------------+----------+----+-----+-------+----------+
;;                                |
;;            +-------------------+
;;            |
;;       +----+----+---+       +------------------------+---------------+
;;       | circle  |   +-------+ current-location-index | circle-length |
;;       +----+----+---+       +------------------------+---------------+
;;            |
;;            |
;;            |
;;    +-------+-------+------------+------------+-------+------------+
;;    | "circle name" | location 1 | location 2 | ...   | location P |
;;    +---------------+------------+------+-----+-------+------------+
;;                                        |
;;                                        |
;;                                        |
;;                               +--------+----------+
;;                               | "file" | position |
;;                               +--------+----------+

;;; Code:
;;; ----------------------------------------------------------------------

;;; Requires
;;; ------------------------------------------------------------

(eval-when-compile
  (require 'duo))

;;; Custom
;;; ------------------------------------------------------------

(defgroup ttorus nil
  "An interface to navigating groups of buffers."
  :tag "ttorus"
  :link '(url-link :tag "Home Page"
                   "https://github.com/chimay/ttorus")
  :link '(emacs-commentary-link
                  :tag "Commentary in ttorus.el" "ttorus.el")
  :prefix "ttorus-"
  :group 'environment
  :group 'extensions
  :group 'convenience)

(defcustom ttorus-prefix-key "s-t"
  "Prefix key for the ttorus key mappings.
Will be processed by `kbd'."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-binding-level 1
  "Whether to activate optional keybindings."
  :type 'integer
  :group 'ttorus)

(defcustom ttorus-verbosity 1
  "Level of verbosity.
1 = normal
2 = light debug
3 = heavy debug."
  :type 'integer
  :group 'ttorus)

(defcustom ttorus-dirname user-emacs-directory
  "The directory where the ttorus are read and written."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-load-on-startup nil
  "Whether to load ttorus on startup of Emacs."
  :type 'boolean
  :group 'ttorus)

(defcustom ttorus-save-on-exit nil
  "Whether to save ttorus on exit of Emacs."
  :type 'boolean
  :group 'ttorus)

(defcustom ttorus-autoread-file "auto.el"
  "The file to load on startup when `ttorus-load-on-startup' is t."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-autowrite-file "auto.el"
  "The file to write before quitting Emacs when `ttorus-save-on-exit' is t."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-backup-number 3
  "Number of backups of ttorus files."
  :type 'integer
  :group 'ttorus)

(defcustom ttorus-maximum-history-elements 50
  "Maximum number of elements in history variables.
See `ttorus-history' and `torus-minibuffer-history'."
  :type 'integer
  :group 'ttorus)

(defcustom ttorus-maximum-horizontal-split 3
  "Maximum number of horizontal split, see `ttorus-split-horizontally'."
  :type 'integer
  :group 'ttorus)

(defcustom ttorus-maximum-vertical-split 4
  "Maximum number of vertical split, see `ttorus-split-vertically'."
  :type 'integer
  :group 'ttorus)

(defcustom ttorus-display-tab-bar nil
  "Whether to display a tab bar in `header-line-format'."
  :type 'boolean
  :group 'ttorus)

(defcustom ttorus-separator-torus-circle " >> "
  "String between ttorus and circle in the dashboard."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-separator-circle-location " > "
  "String between circle and location(s) in the dashboard."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-location-separator " | "
  "String between location(s) in the dashboard."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-prefix-separator "/"
  "String between the prefix and the circle names.
The name of the new circles will be of the form :
\"User_input_prefix `ttorus-prefix-separator' Name_of_the_added_circle\"
without the spaces. If the user enter a blank prefix,
the added circle names remain untouched."
  :type 'string
  :group 'ttorus)

(defcustom ttorus-join-separator " & "
  "String between the names when joining.
The name of the new object will be of the form :
\"Object-1 `ttorus-join-separator' Object-2\"
without the spaces."
  :type 'string
  :group 'ttorus)

;;; Variables
;;; ------------------------------------------------------------

(defvar torus-lace (cons nil nil)
  "Roughly speaking, the lace is a reference to a list of toruses.
More precisely, it’s a cons whose car is a list of toruses.
The cdr of the lace points to a cons which contains :
- the index of the current torus in car
- the length of the list of toruses in cdr
Each torus has a name and a list of circles :
\(torus-name . list-of-circles)
Each circle has a name and a list of locations :
\(circle-name . list-of-locations)
Each location contains a file name and a position :
\(file . position)")

(defvar ttorus-index (cons nil nil)
  "Reference to an alist containing toruses, circles and their locations.
More precisely, it’s a cons whose car is a list of entries.
Each entry has the form :
\((torus-name . circle-name) . (file . position))")

(defvar ttorus-history (cons nil nil)
  "Reference to an alist containing history of locations in all toruses.
More precisely, it’s a cons whose car is a list of entries.
Each entry is a nested cons :
\((torus-name . circle-name) . (file . position))")

(defvar torus-minibuffer-history (list nil)
  "Reference to history of user input in minibuffer.
More precisely, it’s a cons whose car is a list of entries.")

(defvar ttorus-layout (list nil)
  "Reference to a list containing split layout of all circles in all toruses.
More precisely, it’s a cons whose car is a list of entries.
Each entry is a cons :
\((torus-name . circle-name) . layout)
The layout is stored as a character code :
?m manual
?o one window
?h horizontal
?v vertical
?g grid
main window on
  ?l left
  ?r right
  ?t top
  ?b bottom")

(defvar ttorus-line-col (list nil)
  "Reference to an alist storing locations and lines & columns in files.
More precisely, it’s a cons whose car is a list of entries.
Each entry is a cons :
\((file . position) . (line . column))
Allows to display lines & columns.")

;;; Current cons in list
;;; ------------------------------

(defvar torus-cur-torus nil
  "Cons of current torus in `torus-lace'.")

(defvar torus-cur-circle nil
  "Cons of current circle in `torus-cur-torus'.")

(defvar torus-cur-location nil
  "Cons of current location in `torus-cur-circle'.")

(defvar torus-cur-index nil
  "Cons of current entry in `ttorus-index'.")

(defvar torus-cur-history nil
  "Cons of current entry in `ttorus-history'.")

;;; Last cons in list
;;; ------------------------------

(defvar torus-last-torus nil
  "Last torus in `torus-lace'. Just for speed.")

(defvar torus-last-circle nil
  "Last circle in `torus-cur-torus'. Just for speed.")

(defvar torus-last-location nil
  "Last location in `torus-cur-circle'. Just for speed.")

;;; Transient
;;; ------------------------------

(defvar ttorus-markers (list nil)
  "Reference to an alist containing markers to opened files.
More precisely, it’s a cons whose car is a list of entries.
Each entry is a cons :
\((file . position) . marker)
Contain only the files opened in buffers.")

(defvar ttorus-original-header-lines (list nil)
  "Reference to an alist containing header lines before the tab bar changed it.
More precisely, it’s a cons whose car is a list of entries.
Each entry is a cons :
\(buffer . original-header-line)")

;;; Files
;;; ------------------------------

(defvar torus-file-extension ".el"
  "Extension of torus files.")

;;; Prompts
;;; ------------------------------

;;; Empty
;;; ---------------

(defvar ttorus--message-empty-lace
  "Torus Lace is empty. Please add a location with torus-add-location.")

(defvar ttorus--message-empty-torus
  "Torus %s is empty. Please add a location with torus-add-location.")

(defvar ttorus--message-empty-circle
  "Circle %s in Torus %s is empty. Please use torus-add-location.")

;;; Menus
;;; ---------------

(defvar ttorus--message-reset-choice
  "Reset [a] all [l] lace [i] index [h] history [m] minibuffer history [s] split layout\n\
      [p] line & col [C-m] markers [o] orig header line")

(defvar ttorus--message-print-choice
  "Print [a] all [l] lace [i] index [h] history [m] minibuffer history [s] split layout\n\
      [p] line & col [C-m] markers [o] orig header line")

(defvar ttorus--message-alternate-choice
  "Alternate [m] in meta ttorus [t] in ttorus [c] in circle [T] ttoruses [C] circles")

(defvar ttorus--message-reverse-choice
  "Reverse [l] locations [c] circle [d] deep : locations & circles")

(defvar ttorus--message-autogroup-choice
  "Autogroup by [p] path [d] directory [e] extension")

(defvar ttorus--message-batch-choice
  "Run on circle files [e] Elisp code [c] Elisp command \n\
                    [!] Shell command [&] Async Shell command")

(defvar ttorus--message-layout-choice
  "Layout [m] manual [o] one window [h] horizontal [v] vertical [g] grid\n\
       main window on [l] left [r] right [t] top [b] bottom")

;;; Miscellaneous
;;; ---------------

(defvar ttorus--message-file-does-not-exist
  "File %s does not exist anymore. It will be removed from the ttorus.")

(defvar ttorus--message-existent-location
  "Location %s already exists in circle %s")

(defvar ttorus--message-prefix-circle
  "Prefix for the circle of torus %s (leave blank for none) ? ")

(defvar ttorus--message-circle-name-collision
  "Circle name collision. Please add/adjust prefixes to avoid confusion.")

(defvar ttorus--message-replace-torus
  "This will replace the current torus variables. Continue ? ")

;;; Keymaps & Mouse maps
;;; ------------------------------------------------------------

(defvar ttorus-map)

(define-prefix-command 'ttorus-map)

(defvar ttorus-map-mouse-torus (make-sparse-keymap))
(defvar ttorus-map-mouse-circle (make-sparse-keymap))
(defvar ttorus-map-mouse-location (make-sparse-keymap))

;;; Toolbox
;;; ------------------------------------------------------------

;;; Strings
;;; ------------------------------

(defun ttorus--eval-string (string)
  "Eval Elisp code in STRING."
  (eval (car (read-from-string (format "(progn %s)" string)))))

;;; Files
;;; ------------------------------

(defun ttorus--directory (object)
  "Return the last directory component of OBJECT."
  (let* ((filename (pcase object
                     (`(,(and (pred stringp) one) . ,(pred integerp)) one)
                     ((pred stringp) object)))
         (grandpa (file-name-directory (directory-file-name
                                        (file-name-directory
                                         (directory-file-name filename)))))
         (relative (file-relative-name filename grandpa)))
    (directory-file-name (file-name-directory relative))))

(defun ttorus--extension-description (object)
  "Return the extension description of OBJECT."
  (let* ((filename (pcase object
                     (`(,(and (pred stringp) one) . ,(pred integerp)) one)
                     ((pred stringp) object)))
         (extension (file-name-extension filename)))
    (when (> ttorus-verbosity 1)
      (message "filename extension : %s %s" filename extension))
    (pcase extension
      ('nil "Nil")
      ('"" "Ends with a dot")
      ('"sh" "Shell POSIX")
      ('"zsh" "Shell Zsh")
      ('"bash" "Shell Bash")
      ('"org" "Org mode")
      ('"el" "Emacs Lisp")
      ('"vim" "Vim Script")
      ('"py" "Python")
      ('"rb" "Ruby")
      (_ extension))))

;;; Private Functions
;;; ------------------------------------------------------------

;;; State
;;; ------------------------------

(defsubst torus--lace-content ()
  "Return lace content, ie the torus list."
  (car torus-lace))

(defsubst torus--torus-index (&optional index)
  "Return current torus index in lace. Change it to INDEX if non nil."
  (if index
      (setcar (cdr torus-lace) index)
    (car (cdr torus-lace))))

(defsubst torus--lace-length (&optional length)
  "Return lace length. Change it to LENGTH if non nil."
  (if length
      (setcdr (cdr torus-lace) length)
    (cdr (cdr torus-lace))))

(defsubst torus--torus-ref ()
  "Return reference to current torus."
  (car torus-cur-torus))

(defsubst torus--circle-index (&optional index)
  "Return current circle index in torus. Change it to INDEX if non nil."
  (if index
      (setcar (cdr (torus--torus-ref)) index)
    (car (cdr (torus--torus-ref)))))

(defsubst torus--torus-length (&optional length)
  "Return torus length. Change it to LENGTH if non nil."
  (if length
      (setcdr (cdr (torus--torus-ref)) length)
    (cdr (cdr (torus--torus-ref)))))

(defsubst torus--torus-name (&optional name)
  "Return current torus name. Change it to NAME if non nil."
  (if name
      (setcar (car (torus--torus-ref)) name)
    (car (car (torus--torus-ref)))))

(defsubst torus--torus-content ()
  "Return current torus content, ie the circle list."
  (cdr (car (torus--torus-ref))))

(defsubst torus--circle-ref ()
  "Return reference to current circle."
  (car torus-cur-circle))

(defsubst torus--location-index (&optional index)
  "Return current location index in circle. Change it to INDEX if non nil."
  (if index
      (setcar (cdr (torus--circle-ref)) index)
    (car (cdr (torus--circle-ref)))))

(defsubst torus--circle-length (&optional length)
  "Return circle length. Change it to LENGTH if non nil."
  (if length
      (setcdr (cdr (torus--circle-ref)) length)
    (cdr (cdr (torus--circle-ref)))))

(defsubst torus--circle-name (&optional name)
  "Return current torus name. Change it to NAME if non nil."
  (if name
      (setcar (car (torus--circle-ref)) name)
    (car (car (torus--circle-ref)))))

(defsubst torus--circle-content ()
  "Return current torus content, ie the location list."
  (cdr (car (torus--circle-ref))))

;;; Enter the Void
;;; ---------------

(defsubst torus--empty-lace-p ()
  "Whether the torus list is empty."
  (not (torus--lace-content)))

(defsubst torus--empty-torus-p ()
  "Whether current torus is empty.
It’s empty when nil or just a name in car
but no circle in it."
  (not (torus--torus-content)))

(defsubst torus--empty-circle-p ()
  "Whether current circle is empty.
It’s empty when nil or just a name in car
but no location in it."
  (not (torus--circle-content)))

(defsubst torus--set-nil-circle ()
  "Set current circle variables to nil."
  (setq torus-cur-circle nil)
  (setq torus-last-circle nil))

(defsubst torus--set-nil-location ()
  "Set current location variables to nil."
  (setq torus-cur-location nil)
  (setq torus-last-location nil))

;;; Seek to index
;;; ---------------

(defsubst torus--seek-torus (&optional index)
  "Set current torus to the one given by INDEX.
INDEX defaults to current torus index."
  (when index
    (torus--torus-index index))
  (let ((index (torus--torus-index))
        (content (torus--lace-content)))
    (if (and index content)
        (setq torus-cur-torus (duo-at-index index content))
      (setq torus-cur-torus content)))
  (setq torus-last-torus nil))

(defsubst torus--seek-circle (&optional index)
  "Set current circle to the one given by INDEX.
INDEX defaults to current circle index."
  (when index
    (torus--circle-index index))
  (let ((index (torus--circle-index))
        (content (torus--torus-content)))
    (if (and index content)
        (setq torus-cur-circle (duo-at-index index content))
      (setq torus-cur-circle content)))
  (setq torus-last-circle nil))

(defsubst torus--seek-location (&optional index)
  "Set current location to the one given by INDEX.
INDEX defaults to current location index."
  (when index
    (torus--location-index index))
  (let ((index (torus--location-index))
        (content (torus--circle-content)))
    (if (and index content)
        (setq torus-cur-location (duo-at-index index content))
      (setq torus-cur-location content)))
  (setq torus-last-location nil))

;;; Entry
;;; ------------------------------

(defun torus--make-entry (&optional object)
  "Return an entry ((torus-name . circle-name) . (file . position)) from OBJECT.
Use current torus, circle and location if not given."
  (pcase object
    ('nil
     (let ((torus-name (torus--torus-name))
           (circle-name (torus--circle-name))
           (location (car torus-cur-location)))
       (cons (cons torus-name circle-name) location)))
    (`(,(pred stringp) . ,(pred integerp))
     (let ((torus-name (torus--torus-name))
           (circle-name (torus--circle-name)))
       (cons (cons torus-name circle-name) object)))
    (`(,(pred stringp) . (,(pred stringp) . ,(pred integerp)))
     (let ((torus-name (torus--torus-name)))
       (cons (cons torus-name (car object)) (cdr object))))
    (`((,(pred stringp) . ,(pred stringp)) .
       (,(pred stringp) . ,(pred integerp)))
     object)
    (_ (error "Function torus--make-entry : wrong type argument"))))

(defun torus--entry-to-string (object)
  "Return OBJECT in concise string format.
Here are the returned strings, depending of the nature
of OBJECT :
string                             -> string
\((torus . circle) . (file . pos)) -> torus >> circle > file at pos
\(circle . (file . pos))           -> circle > file at Pos
\(file . position)                 -> file at position
"
  (let ((location))
    (pcase object
      (`((,(and (pred stringp) ttorus) . ,(and (pred stringp) circle)) .
         (,(and (pred stringp) file) . ,(and (pred integerp) position)))
       (setq location (cons file position))
       (concat ttorus
               ttorus-separator-torus-circle
               circle
               ttorus-separator-circle-location
               (ttorus--buffer-or-filename location)
               (ttorus--position location)))
      (`(,(and (pred stringp) circle) .
         (,(and (pred stringp) file) . ,(and (pred integerp) position)))
       (setq location (cons file position))
       (concat circle
               ttorus-separator-circle-location
               (ttorus--buffer-or-filename location)
               (ttorus--position location)))
      (`(,(and (pred stringp) file) . ,(and (pred integerp) position))
       (setq location (cons file position))
       (concat (ttorus--buffer-or-filename location)
               (ttorus--position location)))
      ((pred stringp) object)
      (_ (error "Function ttorus--concise : wrong type argument")))))

(defun torus--equal-string-entry-p (one two)
  "Whether the string representations of entries ONE and TWO are equal."
  (equal (torus--entry-to-string (torus--make-entry one))
         (torus--entry-to-string (torus--make-entry two))))

;;; Index
;;; ------------------------------

(defun torus--add-to-index (&optional object)
  "Add an entry built from OBJECT to `ttorus-index'."
  (let* ((entry (torus--make-entry object))
         (index (duo-deref ttorus-index))
         (member (duo-member entry index)))
    (when (and entry
               (not member))
      (setq torus-cur-index
            (duo-ref-insert-at-group-end entry
                                         ttorus-index
                                         #'duo-equal-car-p)))))

;;; History
;;; ------------------------------

(defun torus--add-to-history (&optional object)
  "Add an entry built from OBJECT to `ttorus-history'."
  (let* ((entry (torus--make-entry object))
         (history (duo-deref ttorus-history))
         (member (duo-member entry history)))
    (when entry
      (if member
          (setq torus-cur-history
                (duo-ref-teleport-cons-previous history member ttorus-history))
        (setq torus-cur-history
              (duo-ref-push-and-truncate entry
                                         ttorus-history
                                         ttorus-maximum-history-elements))))))

;;; Split
;;; ------------------------------

(defun ttorus--prefix-argument-split (prefix)
  "Handle prefix argument PREFIX. Used to split."
  (pcase prefix
   ('(4)
    (split-window-below)
    (other-window 1))
   ('(16)
    (split-window-right)
    (other-window 1))))

;;; Commands
;;; ------------------------------------------------------------

;;; Add
;;; ------------------------------

;;;###autoload
(defun ttorus-add-torus (torus-name)
  "Create a new torus named TORUS-NAME in `torus-lace'."
  (interactive
   (list (read-string "Name of the new torus : "
                      nil
                      'torus-minibuffer-history)))
  (let* ((torus (cons (list torus-name) (cons nil 0)))
         (return (duo-ref-add-new torus
                                  torus-lace
                                  torus-last-torus
                                  #'duo-equal-caar-p)))
    (if return
        (progn
          (setq torus-cur-torus return)
          (setq torus-last-torus return)
          (let* ((ind-len (cdr torus-lace))
                 (length (cdr ind-len)))
            (if ind-len
                (progn
                  (setcar ind-len length)
                  (setcdr ind-len (1+ length)))
              (setcdr torus-lace (cons 0 1))))
          (torus--set-nil-circle)
          (torus--set-nil-location)
          torus-cur-torus)
      (message "Torus %s is already present in Torus Lace." torus-name)
      nil)))

;;;###autoload
(defun ttorus-add-circle (circle-name)
  "Add a new circle CIRCLE-NAME to current torus."
  (interactive
   (list
    (read-string "Name of the new circle : "
                 nil
                 'torus-minibuffer-history)))
  (unless torus-cur-torus
    (call-interactively 'ttorus-add-torus))
  (let ((circle (cons (list circle-name) (cons nil 0)))
        (torus-name (torus--torus-name))
        (return))
    (setq return (duo-ref-add-new circle
                                  (torus--torus-ref)
                                  torus-last-circle
                                  #'duo-equal-car-p))
    (if return
        (progn
          (setq torus-cur-circle return)
          (setq torus-last-circle return)
          (let* ((ind-len (cdr (torus--torus-ref)))
                 (length (cdr ind-len)))
            (setcar ind-len length)
            (setcdr ind-len (1+ length)))
          (torus--set-nil-location)
          torus-cur-circle)
      (message "Circle %s is already present in Torus %s."
               circle-name
               torus-name)
      nil)))

;;;###autoload
(defun ttorus-add-location (location)
  "Add LOCATION to current circle."
  (interactive
   (list
    (read-string "New location : "
                 nil
                 'torus-minibuffer-history)))
  (unless torus-cur-torus
    (call-interactively 'ttorus-add-torus))
  (unless torus-cur-circle
    (call-interactively 'ttorus-add-circle))
  (let* ((location (if (consp location)
                       location
                     (car (read-from-string location))))
         (member (duo-member location (torus--circle-content))))
    (if member
        (progn
          (message "Location %s is already present in Torus %s Circle %s."
                   location
                   (torus--torus-name)
                   (torus--circle-name))
          (setq torus-cur-location member)
          (setq torus-cur-index
                (duo-member
                 (torus--make-entry location)
                 (duo-deref ttorus-index)))
          (setq torus-cur-history
                (duo-member (torus--make-entry location)
                            (duo-deref ttorus-history)))
          nil)
      (setq torus-last-location (duo-ref-add location
                                             (torus--circle-ref)
                                             torus-last-location))
      (setq torus-cur-location torus-last-location)
      (let* ((ind-len (cdr (torus--circle-ref)))
             (length (cdr ind-len)))
        (setcar ind-len length)
        (setcdr ind-len (1+ length)))
      (torus--add-to-index)
      (torus--add-to-history)
      torus-cur-location)))

;;;###autoload
(defun ttorus-add-here ()
  "Add current file and point to current circle."
  (interactive)
  (if (buffer-file-name)
      (let* ((pointmark (point-marker))
             (location (cons (buffer-file-name)
                             (marker-position pointmark)))
             (location-line-col (cons location
                                      (cons (line-number-at-pos)
                                            (current-column))))
             (location-marker (cons location pointmark)))
        (ttorus-add-location location)
        (duo-ref-push-new location-line-col ttorus-line-col)
        (duo-ref-push-new location-marker ttorus-markers)
        ;; (torus--status-bar)
        torus-cur-location)
    (message "Buffer must have a filename to be added to the torus.")
    nil))

;;;###autoload
(defun ttorus-add-file (file-name)
  "Add FILE-NAME to the current circle.
The location added will be (file . 1)."
  (interactive (list (read-file-name "File to add : ")))
  (if (file-exists-p file-name)
      (progn
        (find-file file-name)
        (ttorus-add-here))
    (message "File %s does not exist." file-name)
    nil))

;;;###autoload
(defun ttorus-add-buffer (buffer-name)
  "Add BUFFER-NAME at current position to the current circle."
  (interactive (list (read-buffer "File to add : ")))
  (switch-to-buffer buffer-name)
  (ttorus-add-here))

;;; Previous / Next
;;; ------------------------------

;;;###autoload
(defun ttorus-previous-torus ()
  "Jump to the previous ttorus."
  (interactive)
  (if (torus--empty-lace-p)
      (message ttorus--message-empty-lace)
    (setq torus-cur-torus
          (duo-circ-previous torus-cur-torus (torus--lace-content)))
    (let* ((ind-len (cdr torus-lace))
           (index (car ind-len))
           (length (cdr ind-len)))
      (setcar ind-len (mod (1- index) length)))
    (torus--seek-circle)
    (torus--seek-location))
  torus-cur-torus)

;;;###autoload
(defun ttorus-next-torus ()
  "Jump to the next ttorus."
  (interactive)
  (if (torus--empty-lace-p)
      (message ttorus--message-empty-lace)
    (setq torus-cur-torus
          (duo-circ-next torus-cur-torus (torus--lace-content)))
    (let* ((ind-len (cdr torus-lace))
           (index (car ind-len))
           (length (cdr ind-len)))
      (setcar ind-len (mod (1+ index) length)))
    (torus--seek-circle)
    (torus--seek-location))
  torus-cur-torus)

;;;###autoload
(defun ttorus-previous-circle ()
  "Jump to the previous circle."
  (interactive)
  (if (torus--empty-torus-p)
      (message ttorus--message-empty-torus (torus--torus-name))
    (setq torus-cur-circle
          (duo-circ-previous torus-cur-circle
                             (torus--torus-content)))
    (let* ((ind-len (cdr (torus--torus-ref)))
           (index (car ind-len))
           (length (cdr ind-len)))
      (setcar ind-len (mod (1- index) length)))
    (torus--seek-location))
  torus-cur-circle)

;;;###autoload
(defun ttorus-next-circle ()
  "Jump to the next circle."
  (interactive)
  (if (torus--empty-torus-p)
      (message ttorus--message-empty-torus (torus--torus-name))
    (setq torus-cur-circle
          (duo-circ-next torus-cur-circle
                         (torus--torus-content)))
    (let* ((ind-len (cdr (torus--torus-ref)))
           (index (car ind-len))
           (length (cdr ind-len)))
      (setcar ind-len (mod (1+ index) length)))
    (torus--seek-location))
  torus-cur-circle)

;;;###autoload
(defun ttorus-previous-location ()
  "Jump to the previous location."
  (interactive)
  (if (torus--empty-circle-p)
      (message ttorus--message-empty-circle
               (torus--circle-name)
               (torus--torus-name))
    (setq torus-cur-location
          (duo-circ-previous torus-cur-location
                             (torus--circle-content)))
    (let* ((ind-len (cdr (torus--circle-ref)))
           (index (car ind-len))
           (length (cdr ind-len)))
      (setcar ind-len (mod (1- index) length))))
  torus-cur-location)

;;;###autoload
(defun ttorus-next-location ()
  "Jump to the next location."
  (interactive)
  (if (torus--empty-circle-p)
      (message ttorus--message-empty-circle
               (torus--circle-name)
               (torus--torus-name))
    (setq torus-cur-location
          (duo-circ-previous torus-cur-location
                             (torus--circle-content)))
    (let* ((ind-len (cdr (torus--circle-ref)))
           (index (car ind-len))
           (length (cdr ind-len)))
      (setcar ind-len (mod (1+ index) length))))
  torus-cur-location)

;;; ============================================================
;;; From here, it’s a mess
;;; ============================================================

;;; Switch
;;; ------------------------------

;;;###autoload
(defun ttorus-switch-location (location-arg)
  "Jump to LOCATION-NAME location in current circle and torus.
With prefix argument \\[universal-argument], open the buffer in a
horizontal split.
With prefix argument \\[universal-argument] \\[universal-argument], open the
buffer in a vertical split."
  (interactive
   (list
    (completing-read
     "Go to location : "
     (mapcar #'ttorus--concise (cdr (car torus-cur-torus))) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (ttorus--update-position)
  (let* ((circle (cdr (car torus-cur-torus)))
         (index (cl-position location-name circle
                          :test #'ttorus--equal-concise-p))
         (before (cl-subseq circle 0 index))
         (after (cl-subseq circle index)))
    (setcdr (car torus-cur-torus) (append after before)))
  (ttorus--jump))

;;; Predicates
;;; ------------------------------

(defun ttorus--inside-p (&optional buffer)
  "Whether BUFFER belongs to the ttorus.
Argument BUFFER nil means use current buffer."
  (let ((filename (buffer-file-name  (if buffer
                                         buffer
                                       (current-buffer))))
        (locations (append (mapcar 'cdr ttorus-index))))
    (member filename locations)))

;;; Tables
;;; ------------------------------

(defun ttorus--build-index (&optional lace)
  "Return index built from LACE.
Argument LACE nil means build index of `torus-lace'"
  (let ((meta (if lace
                  lace
                torus-lace))
        (ttorus-name)
        (circle-name)
        (ttorus-circle)
        (index)
        (entry))
    (dolist (ttorus meta)
      (setq ttorus-name (car ttorus))
      (dolist (circle (cdr ttorus))
        (setq circle-name (car circle))
        (setq ttorus-circle (cons ttorus-name circle-name))
        (dolist (location (cdr circle))
          (when (> ttorus-verbosity 2)
            (message "Table entry %s" entry))
          (setq entry (cons ttorus-circle location))
          (unless (member entry index)
            (push entry index)))))
    (setq index (reverse index))))

(defun ttorus--narrow-to-torus (&optional ttorus-name index)
  "Narrow an index-like table to entries of TTORUS-NAME.
Argument TTORUS-NAME nil means narrow to current ttorus.
Argument INDEX nil means using `ttorus-index'.
Can be used with `ttorus-index' and `ttorus-history'."
  (let ((index (if index
                   index
                 ttorus-index))
        (ttorus-name (if ttorus-name
                        ttorus-name
                      (car (car torus-cur-torus)))))
    (seq-filter (lambda (elem) (equal (caar elem) ttorus-name))
                index)))

(defun ttorus--narrow-to-circle (&optional ttorus-name circle-name index)
  "Narrow an index-like table to entries of TTORUS-NAME and CIRCLE-NAME.
Argument TTORUS-NAME nil means narrow using current ttorus.
Argument CIRCLE-NAME nil means narrow to current circle.
Argument INDEX nil means using `ttorus-index'.
Can be used with `ttorus-index' and `ttorus-history'."
  (let ((index (if index
                   index
                 ttorus-index))
        (ttorus-name (if ttorus-name
                        ttorus-name
                      (car (car torus-cur-torus))))
        (circle-name (if circle-name
                         circle-name
                       (car (car torus-cur-circle)))))
    (seq-filter (lambda (elem) (and (equal (caar elem) ttorus-name)
                               (equal (cdar elem) circle-name)))
                index)))

(defun ttorus--complete-and-clean-layout ()
  "Fill `ttorus-layout' from missing elements. Delete useless ones."
  (let ((paths (mapcar #'car ttorus-index)))
    (delete-dups paths)
    (dolist (elem paths)
      (unless (assoc elem ttorus-layout)
        (push (cons elem ?m) ttorus-layout)))
    (dolist (elem ttorus-layout)
      (unless (member (car elem) paths)
        (setq ttorus-layout (ttorus--assoc-delete-all (car elem) ttorus-layout))))
    (setq ttorus-layout (reverse ttorus-layout))))

(defun ttorus--apply-or-push-layout ()
  "Apply layout of current circle, or add default is not present."
  (let* ((path (cons (car (car torus-cur-torus))
                     (car (car torus-cur-circle))))
         (entry (assoc path ttorus-layout)))
    (if entry
        (ttorus-layout-menu (cdr entry))
      (push (cons path ?m) ttorus-layout))))

;;; Updates
;;; ------------------------------

(defun ttorus--update-position ()
  "Update position in current location.
Do nothing if file does not match current buffer."
  (unless (torus--empty-circle-p)
    (let* ((ttorus-circle (cons (car torus-cur-torus)
                               (car torus-cur-circle)))
           (old-location (torus-cur-location))
           (old-entry torus-cur-index)
           (old-here (cdr old-location))
           (file (car old-location))
           (here (point))
           (marker (point-marker))
           (line-col (cons (line-number-at-pos) (current-column)))
           (new-location (cons file here))
           (new-entry (cons ttorus-circle new-location))
           (new-location-line-col (cons new-location line-col))
           (new-location-marker (cons new-location marker)))
      (when (> ttorus-verbosity 2)
        (message "Update position -->")
        (message "here old : %s %s" here old-here)
        (message "old-location : %s" old-location)
        (message "loc history : %s" (caar ttorus-old-history))
        (message "assoc index : %s" (assoc old-location ttorus-table)))
      (when (and (equal file (buffer-file-name (current-buffer)))
                 (equal old-entry (car ttorus-history))
                 (not (equal here old-here)))
        (when (> ttorus-verbosity 2)
          (message "Old location : %s" old-location)
          (message "New location : %s" new-location))
        (setcar (cdr (cadr torus-cur-torus)) new-location)
        (if (member old-entry ttorus-index)
            (setcar (member old-entry ttorus-index) new-entry)
          (setq ttorus-index (ttorus--build-index)))
        (if (member old-entry ttorus-history)
            (setcar (member old-entry ttorus-history)
                    new-entry)
          (ttorus--update-meta-history))
        (if (assoc old-location ttorus-line-col)
            (progn
              (setcdr (assoc old-location ttorus-line-col) line-col)
              (setcar (assoc old-location ttorus-line-col) new-location))
          (push new-location-line-col ttorus-line-col))
        (if (assoc old-location ttorus-markers)
            (progn
              (setcdr (assoc old-location ttorus-markers) marker)
              (setcar (assoc old-location ttorus-markers) new-location))
          (push new-location-marker ttorus-markers))))))

(defun ttorus--jump ()
  "Jump to current location (buffer & position) in ttorus.
Add the location to `ttorus-markers' if not already present."
  (when (and torus-cur-torus
             (listp torus-cur-torus)
             (car torus-cur-torus)
             (listp (car torus-cur-torus))
             (> (length (car torus-cur-torus)) 1))
    (let* ((location (car (cdr (car torus-cur-torus))))
           (circle-name (caar torus-cur-torus))
           (ttorus-name (caar ttorus-meta))
           (circle-torus (cons circle-name ttorus-name))
           (location-circle (cons location circle-name))
           (location-circle-torus (cons location circle-torus))
           (file (car location))
           (position (cdr location))
           (bookmark (cdr (assoc location ttorus-markers)))
           (buffer (when bookmark
                     (marker-buffer bookmark))))
      (if (and bookmark buffer (buffer-live-p buffer))
          (progn
            (when (> ttorus-verbosity 2)
              (message "Found %s in markers" bookmark))
            (when (not (equal buffer (current-buffer)))
              (switch-to-buffer buffer))
            (goto-char bookmark))
        (when (> ttorus-verbosity 2)
          (message "Found %s in ttorus" location))
        (when bookmark
          (setq ttorus-markers (ttorus--assoc-delete-all location ttorus-markers)))
        (if (file-exists-p file)
            (progn
              (when (> ttorus-verbosity 1)
                (message "Opening file %s at %s" file position))
              (find-file file)
              (goto-char position)
              (push (cons location (point-marker)) ttorus-markers))
          (message (format ttorus--message-file-does-not-exist file))
          (setcdr (car torus-cur-torus) (cl-remove location (cdr (car torus-cur-torus))))
          (setq ttorus-line-col (ttorus--assoc-delete-all location ttorus-line-col))
          (setq ttorus-markers (ttorus--assoc-delete-all location ttorus-markers))
          (setq ttorus-table (cl-remove location-circle ttorus-table))
          (setq ttorus-index (cl-remove location-circle-torus ttorus-index))
          (setq ttorus-old-history (cl-remove location-circle ttorus-old-history))
          (setq ttorus-history (cl-remove location-circle-torus ttorus-history))))
      (ttorus--update-history)
      (ttorus--update-meta-history)
      (torus--status-bar))
    (recenter)))

;;; Switch
;;; ------------------------------

(defun ttorus--switch (location-circle)
  "Jump to circle and location countained in LOCATION-CIRCLE."
  (unless (and location-circle
               (consp location-circle)
               (consp (car location-circle)))
    (error "Function ttorus--switch : wrong type argument"))
  (ttorus--update-position)
  (let* ((circle-name (cdr location-circle))
         (circle (assoc circle-name torus-cur-torus))
         (index (cl-position circle torus-cur-torus :test #'equal))
         (before (cl-subseq torus-cur-torus 0 index))
         (after (cl-subseq torus-cur-torus index)))
    (if index
        (setq torus-cur-torus (append after before))
      (message "Circle not found.")))
  (let* ((circle (cdr (car torus-cur-torus)))
         (location (car location-circle))
         (index (cl-position location circle :test #'equal))
         (before (cl-subseq circle 0 index))
         (after (cl-subseq circle index)))
    (if index
        (setcdr (car torus-cur-torus) (append after before))
      (message "Location not found.")))
  (ttorus--jump)
  (ttorus--apply-or-push-layout))

(defun ttorus--meta-switch (entry)
  "Jump to ttorus, circle and location countained in ENTRY."
  (unless (and entry
               (consp entry)
               (consp (car entry))
               (consp (cdr entry)))
    (error "Function ttorus--switch : wrong type argument"))
  (when (> ttorus-verbosity 2)
    (message "meta switch entry : %s" entry))
  (ttorus--update-meta)
  (let* ((ttorus-name (caar entry))
         (ttorus (assoc ttorus-name ttorus-meta))
         (index (cl-position ttorus ttorus-meta :test #'equal))
         (before (cl-subseq ttorus-meta 0 index))
         (after (cl-subseq ttorus-meta index)))
    (if index
        (setq ttorus-meta (append after before))
      (message "ttorus not found.")))
  (ttorus--update-from-meta)
  (ttorus--build-table)
  (setq ttorus-index (ttorus--build-index))
  (ttorus--complete-and-clean-layout)
  (let* ((circle-name (cdar entry))
         (circle (assoc circle-name torus-cur-torus))
         (index (cl-position circle torus-cur-torus :test #'equal))
         (before (cl-subseq torus-cur-torus 0 index))
         (after (cl-subseq torus-cur-torus index)))
    (if index
        (setq torus-cur-torus (append after before))
      (message "Circle not found.")))
  (let* ((circle (cdr (car torus-cur-torus)))
         (location (cdr entry))
         (index (cl-position location circle :test #'equal))
         (before (cl-subseq circle 0 index))
         (after (cl-subseq circle index)))
    (if index
        (setcdr (car torus-cur-torus) (append after before))
      (message "Location not found.")))
  (ttorus--jump)
  (ttorus--apply-or-push-layout))

;;; Modifications
;;; ------------------------------

(defun ttorus--prefix-circles (prefix ttorus-name)
  "Return vars of TTORUS-NAME with PREFIX to the circle names."
  (unless (and (stringp prefix) (stringp ttorus-name))
    (error "Function ttorus--prefix-circles : wrong type argument"))
  (let* ((entry (cdr (assoc ttorus-name ttorus-meta)))
         (ttorus (copy-lace (cdr (assoc "ttorus" entry))))
         (history (copy-lace (cdr (assoc "history" entry)))))
    (if (> (length prefix) 0)
        (progn
          (message "Prefix is %s" prefix)
          (dolist (elem ttorus)
            (setcar elem
                    (concat prefix ttorus-prefix-separator (car elem))))
          (dolist (elem history)
            (setcdr elem
                    (concat prefix ttorus-prefix-separator (cdr elem)))))
      (message "Prefix is blank"))
    (list ttorus history)))

;;; Windows
;;; ------------------------------

(defsubst ttorus--windows ()
  "Windows displaying a ttorus buffer."
  (seq-filter (lambda (elem) (ttorus--inside-p (window-buffer elem)))
              (window-list)))

(defun ttorus--main-windows ()
  "Return main window of layout."
  (let* ((windows (ttorus--windows))
         (columns (mapcar #'window-text-width windows))
         (max-columns (when columns
                    (eval `(max ,@columns))))
         (widest)
         (lines)
         (max-lines)
         (biggest))
    (when windows
      (dolist (index (number-sequence 0 (1- (length windows))))
        (when (equal (nth index columns) max-columns)
          (push (nth index windows) widest)))
      (setq lines (mapcar #'window-text-height widest))
      (setq max-lines (eval `(max ,@lines)))
      (dolist (index (number-sequence 0 (1- (length widest))))
        (when (equal (nth index lines) max-lines)
          (push (nth index widest) biggest)))
      (when (> ttorus-verbosity 2)
        (message "toruw windows : %s" windows)
        (message "columns : %s" columns)
        (message "max-columns : %s" max-columns)
        (message "widest : %s" widest)
        (message "lines : %s" lines)
        (message "max-line : %s" max-lines)
        (message "biggest : %s" biggest))
      biggest)))

;;; Strings
;;; ------------------------------

(defun ttorus--buffer-or-filename (location)
  "Return buffer name of LOCATION if existent in `ttorus-markers', file basename otherwise."
  (unless (consp location)
    (error "Function ttorus--buffer-or-filename : wrong type argument"))
  (let* ((bookmark (cdr (assoc location ttorus-markers)))
         (buffer (when bookmark
                   (marker-buffer bookmark))))
    (if buffer
        (buffer-name buffer)
      (file-name-nondirectory (car location)))))

(defun ttorus--position (location)
  "Return position in LOCATION in raw format or in line & column if available.
Line & Columns are stored in `ttorus-line-col'."
  (let ((entry (assoc location ttorus-line-col)))
    (if entry
        (format " at line %s col %s" (cadr entry) (cddr entry))
      (format " at position %s" (cdr location)))))

(defun ttorus--needle (location)
  "Return LOCATION in short string format.
Shorter than concise. Used for dashboard and tabs."
  (unless (consp location)
    (error "Function ttorus--needle : wrong type argument"))
  (let* ((entry (assoc location ttorus-line-col))
         (position (if entry
                       (format " : %s" (cadr entry))
                     (format " . %s" (cdr location)))))
    (if (equal location (cadar torus-cur-torus))
        (concat "[ "
                (ttorus--buffer-or-filename location)
                position
                " ]")
      (concat (ttorus--buffer-or-filename location)
              position))))

(defun ttorus--dashboard ()
  "Display summary of current ttorus, circle and location."
  (if ttorus-meta
      (if (> (length (car torus-cur-torus)) 1)
          (let*
              ((locations (string-join (mapcar #'ttorus--needle
                                               (cdar torus-cur-torus)) " | ")))
            (format (concat " %s"
                            ttorus-separator-torus-circle
                            "%s"
                            ttorus-separator-circle-location
                            "%s")
                     (caar ttorus-meta)
                     (caar torus-cur-torus)
                     locations))
        (message ttorus--message-empty-circle (car (car torus-cur-torus))))
    (message ttorus--message-empty-lace)))

;;; Files
;;; ------------------------------

(defun ttorus--roll-backups (filename)
  "Roll backups of FILENAME."
  (unless (stringp filename)
    (error "Function ttorus--roll-backups : wrong type argument"))
  (let ((file-list (list filename))
        (file-src)
        (file-dest))
    (dolist (iter (number-sequence 1 ttorus-backup-number))
      (push (concat filename "." (prin1-to-string iter)) file-list))
    (while (> (length file-list) 1)
      (setq file-dest (pop file-list))
      (setq file-src (car file-list))
      (when (> ttorus-verbosity 2)
        (message "files %s %s" file-src file-dest))
      (when (and file-src (file-exists-p file-src))
        (when (> ttorus-verbosity 2)
          (message "copy %s -> %s" file-src file-dest))
        (copy-file file-src file-dest t)))))

;;; Tab bar
;;; ------------------------------

(defun ttorus--eval-tab ()
  "Build tab bar."
  (when ttorus-meta
      (let*
          ((locations (mapcar #'ttorus--needle (cdar torus-cur-torus)))
           (tab-string))
        (setq tab-string
              (propertize (format (concat " %s"
                                          ttorus-separator-torus-circle)
                                  (caar ttorus-meta))
                          'keymap ttorus-map-mouse-torus))
        (setq tab-string
              (concat tab-string
                      (propertize (format (concat "%s"
                                                  ttorus-separator-circle-location)
                                          (caar torus-cur-torus))
                                  'keymap ttorus-map-mouse-circle)))
        (dolist (filepos locations)
          (setq tab-string
                (concat tab-string (propertize filepos
                                               'keymap ttorus-map-mouse-location)))
          (setq tab-string (concat tab-string ttorus-location-separator)))
        tab-string)))

(defun torus--status-bar ()
  "Display status bar, as tab bar or as info in echo area."
  (let* ((main-windows (ttorus--main-windows))
         (current-window (selected-window))
         (buffer (current-buffer))
         (original (assoc buffer ttorus-original-header-lines))
         (eval-tab '(:eval (ttorus--eval-tab))))
    (when (> ttorus-verbosity 2)
      (pp ttorus-original-header-lines)
      (message "original : %s" original)
      (message "cdr original : %s" (cdr original)))
    (if (and ttorus-display-tab-bar
             (member current-window main-windows))
        (progn
          (unless original
            (push (cons buffer header-line-format)
                  ttorus-original-header-lines))
          (unless (equal header-line-format eval-tab)
            (when (> ttorus-verbosity 2)
              (message "Set :eval in header-line-format."))
            (setq header-line-format eval-tab)))
      (when original
        (setq header-line-format (cdr original))
        (setq ttorus-original-header-lines
              (ttorus--assoc-delete-all buffer
                                       ttorus-original-header-lines)))
      (message (ttorus--dashboard)))))

;;; Compatibility
;;; ------------------------------------------------------------

(defun ttorus--convert-meta-to-lace ()
  "Convert old `ttorus-meta' format to new `torus-lace'."
  (setq torus-lace
        (mapcar (lambda (elem)
                  (cons (car elem)
                        (ttorus--assoc-value "ttorus" (cdr elem))))
                ttorus-meta)))

(defun ttorus--convert-old-vars ()
  "Convert old variables format to new one."
  (ttorus--convert-meta-to-lace)
  (when (intern-soft "ttorus-meta-index")
    (when ttorus-meta-index
      (setq ttorus-index (ttorus--build-index)))
    (unintern "ttorus-meta-index"))
  (when (intern-soft "ttorus-meta-history")
    (when ttorus-meta-history
      ;;TODO: more checks
      (setq ttorus-history ttorus-meta-history))
    (unintern "ttorus-meta-history")))

;;; Hooks & Advices
;;; ------------------------------------------------------------

;;;###autoload
(defun ttorus-quit ()
  "Write ttorus before quit."
  (when ttorus-save-on-exit
    (if ttorus-autowrite-file
        ;; TODO : complete path by ttorus-dirname if necessary
        (ttorus-write ttorus-autowrite-file)
      (when (y-or-n-p "Write ttorus ? ")
        (call-interactively 'ttorus-write))))
  ;; To be sure they will be nil at startup, even if some plugin saved
  ;; global variables
  (ttorus-reset-menu ?a))

;;;###autoload
(defun ttorus-start ()
  "Read ttorus on startup."
  (when ttorus-load-on-startup
    (if ttorus-autoread-file
        ;; TODO : complete path by ttorus-dirname if necessary
        (ttorus-read ttorus-autoread-file)
      (message "Set ttorus-autoread-file if you want to load it."))))

;;;###autoload
(defun ttorus-after-save-torus-file ()
  "Ask whether to read ttorus file after edition."
  (let* ((filename (buffer-file-name (current-buffer)))
         (directory (file-name-directory filename))
         (ttorus-dir (expand-file-name (file-name-as-directory ttorus-dirname))))
    (when (> ttorus-verbosity 2)
      (message "filename : %s" filename)
      (message "filename directory : %s" directory)
      (message "ttorus directory : %s" ttorus-dir))
    (when (equal directory ttorus-dir)
      (when (y-or-n-p "Apply changes to current ttorus variables ? ")
        (ttorus-read filename)))))

;;;###autoload
(defun ttorus-advice-switch-buffer (&rest args)
  "Advice to `switch-to-buffer'. ARGS are irrelevant."
  (when (> ttorus-verbosity 2)
    (message "Advice called with args %s" args))
  (when (and torus-cur-torus (ttorus--inside-p))
    (ttorus--update-position)))

;;; Commands
;;; ------------------------------------------------------------

;;;###autoload
(defun ttorus-init ()
  "Initialize ttorus. Add hooks and advices.
Create `ttorus-dirname' if needed."
  (interactive)
  (add-hook 'emacs-startup-hook 'ttorus-start)
  (add-hook 'kill-emacs-hook 'ttorus-quit)
  (add-hook 'after-save-hook 'ttorus-after-save-torus-file)
  (advice-add #'switch-to-buffer :before #'ttorus-advice-switch-buffer)
  (unless (file-exists-p ttorus-dirname)
    (make-directory ttorus-dirname)))

;;;###autoload
(defun ttorus-install-default-bindings ()
  "Install default keybindings."
  (interactive)
  ;; Keymap
  (if (stringp ttorus-prefix-key)
      (global-set-key (kbd ttorus-prefix-key) 'ttorus-map)
    (global-set-key ttorus-prefix-key 'ttorus-map))
  (when (>= ttorus-binding-level 0)
    (define-key ttorus-map (kbd "i") 'ttorus-info)
    (define-key ttorus-map (kbd "c") 'ttorus-add-circle)
    (define-key ttorus-map (kbd "l") 'ttorus-add-location)
    (define-key ttorus-map (kbd "f") 'ttorus-add-file)
    (define-key ttorus-map (kbd "+") 'ttorus-add-torus)
    (define-key ttorus-map (kbd "*") 'ttorus-add-copy-of-torus)
    (define-key ttorus-map (kbd "<left>") 'ttorus-previous-circle)
    (define-key ttorus-map (kbd "<right>") 'ttorus-next-circle)
    (define-key ttorus-map (kbd "<up>") 'ttorus-previous-location)
    (define-key ttorus-map (kbd "<down>") 'ttorus-next-location)
    (define-key ttorus-map (kbd "C-p") 'ttorus-previous-torus)
    (define-key ttorus-map (kbd "C-n") 'ttorus-next-torus)
    (define-key ttorus-map (kbd "SPC") 'ttorus-switch-circle)
    (define-key ttorus-map (kbd "=") 'ttorus-switch-location)
    (define-key ttorus-map (kbd "@") 'ttorus-switch-torus)
    (define-key ttorus-map (kbd "s") 'ttorus-search)
    (define-key ttorus-map (kbd "S") 'ttorus-meta-search)
    (define-key ttorus-map (kbd "d") 'ttorus-delete-location)
    (define-key ttorus-map (kbd "D") 'ttorus-delete-circle)
    (define-key ttorus-map (kbd "-") 'ttorus-delete-torus)
    (define-key ttorus-map (kbd "r") 'ttorus-read)
    (define-key ttorus-map (kbd "w") 'ttorus-write)
    (define-key ttorus-map (kbd "e") 'ttorus-edit))
  (when (>= ttorus-binding-level 1)
    (define-key ttorus-map (kbd "<next>") 'ttorus-history-older)
    (define-key ttorus-map (kbd "<prior>") 'ttorus-history-newer)
    (define-key ttorus-map (kbd "h") 'ttorus-search-history)
    (define-key ttorus-map (kbd "H") 'ttorus-search-meta-history)
    (define-key ttorus-map (kbd "a") 'ttorus-alternate-menu)
    (define-key ttorus-map (kbd "^") 'ttorus-alternate-in-same-torus)
    (define-key ttorus-map (kbd "<") 'ttorus-alternate-circles)
    (define-key ttorus-map (kbd ">") 'ttorus-alternate-in-same-circle)
    (define-key ttorus-map (kbd "n") 'ttorus-rename-circle)
    (define-key ttorus-map (kbd "N") 'ttorus-rename-torus)
    (define-key ttorus-map (kbd "m") 'ttorus-move-location)
    (define-key ttorus-map (kbd "M") 'ttorus-move-circle)
    (define-key ttorus-map (kbd "M-m") 'ttorus-move-torus)
    (define-key ttorus-map (kbd "v") 'ttorus-move-location-to-circle)
    (define-key ttorus-map (kbd "V") 'ttorus-move-circle-to-torus)
    (define-key ttorus-map (kbd "y") 'ttorus-copy-location-to-circle)
    (define-key ttorus-map (kbd "Y") 'ttorus-copy-circle-to-torus)
    (define-key ttorus-map (kbd "j") 'ttorus-join-circles)
    (define-key ttorus-map (kbd "J") 'ttorus-join-toruses)
    (define-key ttorus-map (kbd "#") 'ttorus-layout-menu))
  (when (>= ttorus-binding-level 2)
    (define-key ttorus-map (kbd "o") 'ttorus-reverse-menu)
    (define-key ttorus-map (kbd ":") 'ttorus-prefix-circles-of-current-torus)
    (define-key ttorus-map (kbd "g") 'ttorus-autogroup-menu)
    (define-key ttorus-map (kbd "!") 'ttorus-batch-menu))
  (when (>= ttorus-binding-level 3)
    (define-key ttorus-map (kbd "p") 'ttorus-print-menu)
    (define-key ttorus-map (kbd "z") 'ttorus-reset-menu)
    (define-key ttorus-map (kbd "C-d") 'ttorus-delete-current-location)
    (define-key ttorus-map (kbd "M-d") 'ttorus-delete-current-circle))
  ;; Mouse
  (define-key ttorus-map-mouse-torus [header-line mouse-1] 'ttorus-switch-torus)
  (define-key ttorus-map-mouse-torus [header-line mouse-2] 'ttorus-alternate-toruses)
  (define-key ttorus-map-mouse-torus [header-line mouse-3] 'ttorus-meta-search)
  (define-key ttorus-map-mouse-torus [header-line mouse-4] 'ttorus-previous-torus)
  (define-key ttorus-map-mouse-torus [header-line mouse-5] 'ttorus-next-torus)
  (define-key ttorus-map-mouse-circle [header-line mouse-1] 'ttorus-switch-circle)
  (define-key ttorus-map-mouse-circle [header-line mouse-2] 'ttorus-alternate-circles)
  (define-key ttorus-map-mouse-circle [header-line mouse-3] 'ttorus-search)
  (define-key ttorus-map-mouse-circle [header-line mouse-4] 'ttorus-previous-circle)
  (define-key ttorus-map-mouse-circle [header-line mouse-5] 'ttorus-next-circle)
  (define-key ttorus-map-mouse-location [header-line mouse-1] 'ttorus-tab-mouse)
  (define-key ttorus-map-mouse-location [header-line mouse-2] 'ttorus-alternate-in-meta)
  (define-key ttorus-map-mouse-location [header-line mouse-3] 'ttorus-switch-location)
  (define-key ttorus-map-mouse-location [header-line mouse-4] 'ttorus-previous-location)
  (define-key ttorus-map-mouse-location [header-line mouse-5] 'ttorus-next-location))

;;;###autoload
(defun ttorus-reset-menu (choice)
  "Reset CHOICE variables to nil."
  (interactive
   (list (read-key ttorus--message-reset-choice)))
  (let ((varlist))
    (pcase choice
      (?3 (push 'torus-lace varlist))
      (?i (push 'ttorus-index varlist))
      (?h (push 'ttorus-history varlist))
      (?m (push 'torus-minibuffer-history varlist))
      (?l (push 'ttorus-layout varlist))
      (?& (push 'ttorus-line-col varlist))
      (?\^m (push 'ttorus-markers varlist))
      (?o (push 'ttorus-original-header-lines varlist))
      (?a (setq varlist (list 'torus-lace
                              'ttorus-index
                              'ttorus-history
                              'torus-minibuffer-history
                              'ttorus-layout
                              'ttorus-line-col
                              'ttorus-markers
                              'ttorus-original-header-lines)))
      (?\a (message "Reset cancelled by Ctrl-G."))
      (_ (message "Invalid key.")))
    (dolist (var varlist)
      (when (> ttorus-verbosity 1)
        (message "%s -> nil" (symbol-name var)))
      (set var nil))))

;;; Print
;;; ------------------------------

;;;###autoload
(defun ttorus-info ()
  "Print local info : circle name and locations."
  (interactive)
  (message (ttorus--dashboard)))

;;;###autoload
(defun ttorus-print-menu (choice)
  "Print CHOICE variables."
  (interactive
   (list (read-key ttorus--message-print-choice)))
  (let ((varlist)
        (window (view-echo-area-messages)))
    (pcase choice
      (?3 (push 'torus-lace varlist))
      (?i (push 'ttorus-index varlist))
      (?h (push 'ttorus-history varlist))
      (?m (push 'torus-minibuffer-history varlist))
      (?l (push 'ttorus-layout varlist))
      (?& (push 'ttorus-line-col varlist))
      (?\^m (push 'ttorus-markers varlist))
      (?o (push 'ttorus-original-header-lines varlist))
      (?a (setq varlist (list 'torus-lace
                              'ttorus-index
                              'ttorus-history
                              'torus-minibuffer-history
                              'ttorus-layout
                              'ttorus-line-col
                              'ttorus-markers
                              'ttorus-original-header-lines)))
      (?\a (delete-window window)
           (message "Print cancelled by Ctrl-G."))
      (_ (message "Invalid key.")))
    (dolist (var varlist)
      (message "%s" (symbol-name var))
      (pp (symbol-value var)))))

;;; Add
;;; ------------------------------

;;;###autoload
(defun ttorus-add-copy-of-torus (ttorus-name)
  "Create a new ttorus named TTORUS-NAME as copy of the current ttorus."
  (interactive
   (list (read-string "Name of the new ttorus : "
                      nil
                      'torus-minibuffer-history)))
  (setq torus-cur-torus (copy-lace torus-cur-torus))
  (if torus-cur-torus
      (setcar torus-cur-torus ttorus-name)
    (setq torus-cur-torus (list ttorus-name)))
  (if torus-lace
      (duo-add-new torus-cur-torus torus-lace)
    (setq torus-lace (list torus-cur-torus))))

;;; Navigate
;;; ------------------------------

;;;###autoload
(defun ttorus-switch-circle (circle-name)
  "Jump to CIRCLE-NAME circle.
With prefix argument \\[universal-argument], open the buffer in a
horizontal split.
With prefix argument \\[universal-argument] \\[universal-argument], open the
buffer in a vertical split."
  (interactive
   (list (completing-read
          "Go to circle : "
          (mapcar #'car torus-cur-torus) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (ttorus--update-position)
  (let* ((circle (assoc circle-name torus-cur-torus))
         (index (cl-position circle torus-cur-torus :test #'equal))
         (before (cl-subseq torus-cur-torus 0 index))
         (after (cl-subseq torus-cur-torus index)))
    (setq torus-cur-torus (append after before)))
  (ttorus--jump)
  (ttorus--apply-or-push-layout))

;;;###autoload
(defun ttorus-switch-torus (ttorus-name)
  "Jump to TTORUS-NAME ttorus.
With prefix argument \\[universal-argument], open the buffer in a
horizontal split.
With prefix argument \\[universal-argument] \\[universal-argument], open the
buffer in a vertical split."
  (interactive
   (list (completing-read
          "Go to ttorus : "
          (mapcar #'car ttorus-meta) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (ttorus--update-meta)
  (let* ((ttorus (assoc ttorus-name ttorus-meta))
         (index (cl-position ttorus ttorus-meta :test #'equal))
         (before (cl-subseq ttorus-meta 0 index))
         (after (cl-subseq ttorus-meta index)))
    (if index
        (setq ttorus-meta (append after before))
      (message "ttorus not found.")))
  (ttorus--update-from-meta)
  (ttorus--build-table)
  (setq ttorus-index (ttorus--build-index))
  (ttorus--complete-and-clean-layout)
  (ttorus--jump)
  (ttorus--apply-or-push-layout))

;;; Search
;;; ------------------------------

;;;###autoload
(defun ttorus-search (location-name)
  "Search LOCATION-NAME in the ttorus.
Go to the first matching circle and location."
  (interactive
   (list
    (completing-read
     "Search location in ttorus : "
     (mapcar #'ttorus--concise ttorus-table) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (let* ((location-circle
          (cl-find
           location-name ttorus-table
           :test #'ttorus--equal-concise-p)))
    (ttorus--switch location-circle)))


;;;###autoload
(defun ttorus-meta-search (name)
  "Search location NAME in all ttoruses.
Go to the first matching ttorus, circle and location."
  (interactive
   (list
    (completing-read
     "Search location in all ttoruses : "
     (mapcar #'ttorus--concise ttorus-index) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (let* ((entry
          (cl-find
           name ttorus-index
           :test #'ttorus--equal-concise-p)))
    (ttorus--meta-switch entry)))

;;; History
;;; ------------------------------

;;;###autoload
(defun ttorus-history-newer ()
  "Go to newer location in history."
  (interactive)
  (if torus-cur-torus
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if ttorus-old-history
            (progn
              (setq ttorus-old-history (append (last ttorus-old-history) (butlast ttorus-old-history)))
              (ttorus--switch (car ttorus-old-history)))
          (message "History is empty.")))
    (message ttorus--message-empty-torus)))

;;;###autoload
(defun ttorus-history-older ()
  "Go to older location in history."
  (interactive)
  (if torus-cur-torus
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if ttorus-old-history
            (progn
              (setq ttorus-old-history (append (cdr ttorus-old-history) (list (car ttorus-old-history))))
              (ttorus--switch (car ttorus-old-history)))
          (message "History is empty.")))
    (message ttorus--message-empty-torus)))

;;;###autoload
(defun ttorus-search-history (location-name)
  "Search LOCATION-NAME in `ttorus-old-history'."
  (interactive
   (list
    (completing-read
     "Search location in history : "
     (mapcar #'ttorus--concise ttorus-old-history) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (when ttorus-old-history
    (let* ((index (cl-position location-name ttorus-old-history
                            :test #'ttorus--equal-concise-p))
           (before (cl-subseq ttorus-old-history 0 index))
           (element (nth index ttorus-old-history))
           (after (cl-subseq ttorus-old-history (1+ index))))
      (setq ttorus-old-history (append (list element) before after)))
    (ttorus--switch (car ttorus-old-history))))

;;;###autoload
(defun ttorus-search-meta-history (location-name)
  "Search LOCATION-NAME in `ttorus-history'."
  (interactive
   (list
    (completing-read
     "Search location in history : "
     (mapcar #'ttorus--concise ttorus-history) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (when ttorus-history
    (let* ((index (cl-position location-name ttorus-history
                            :test #'ttorus--equal-concise-p))
           (before (cl-subseq ttorus-history 0 index))
           (element (nth index ttorus-history))
           (after (cl-subseq ttorus-history (1+ index))))
      (setq ttorus-history (append (list element) before after)))
    (ttorus--meta-switch (car ttorus-history))))

;;; Alternate
;;; ------------------------------

;;;###autoload
(defun ttorus-alternate-in-meta ()
  "Alternate last two locations in meta history.
If outside the ttorus, just return inside, to the last ttorus location."
  (interactive)
  (if ttorus-meta
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if (ttorus--inside-p)
            (if (and ttorus-history
                     (>= (length ttorus-history) 2))
                (progn
                  (ttorus--update-meta)
                  (setq ttorus-history (append (list (car (cdr ttorus-history)))
                                                   (list (car ttorus-history))
                                                   (nthcdr 2 ttorus-history)))
                  (ttorus--meta-switch (car ttorus-history)))
              (message "Meta history has less than two elements."))
          (ttorus--jump)))
    (message ttorus--message-empty-lace)))

;;;###autoload
(defun ttorus-alternate-in-same-torus ()
  "Alternate last two locations in history belonging to the current circle.
If outside the ttorus, just return inside, to the last ttorus location."
  (interactive)
  (if torus-cur-torus
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if (ttorus--inside-p)
            (if (and ttorus-old-history
                     (>= (length ttorus-old-history) 2))
                (progn
                  (ttorus--update-meta)
                  (setq ttorus-old-history (append (list (car (cdr ttorus-old-history)))
                                              (list (car ttorus-old-history))
                                              (nthcdr 2 ttorus-old-history)))
                  (ttorus--switch (car ttorus-old-history)))
              (message "History has less than two elements."))
          (ttorus--jump)))
    (message ttorus--message-empty-torus)))

;;;###autoload
(defun ttorus-alternate-in-same-circle ()
  "Alternate last two locations in history belonging to the current circle.
If outside the ttorus, just return inside, to the last ttorus location."
  (interactive)
  (if torus-cur-torus
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if (ttorus--inside-p)
            (if (and ttorus-old-history
                     (>= (length ttorus-old-history) 2))
                (progn
                  (ttorus--update-meta)
                  (let ((history ttorus-old-history)
                        (circle (car (car torus-cur-torus)))
                        (element)
                        (location-circle))
                    (pop history)
                    (while (and (not location-circle) history)
                      (setq element (pop history))
                      (when (equal circle (cdr element))
                        (setq location-circle element)))
                    (if location-circle
                        (ttorus--switch location-circle)
                      (message "No alternate file in same circle in history."))))
              (message "History has less than two elements."))
          (ttorus--jump)))
    (message ttorus--message-empty-torus)))

;;;###autoload
(defun ttorus-alternate-toruses ()
  "Alternate last two ttoruses in meta history.
If outside the ttorus, just return inside, to the last ttorus location."
  (interactive)
  (if ttorus-meta
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if (ttorus--inside-p)
            (if (and ttorus-history
                     (>= (length ttorus-history) 2))
                (progn
                  (ttorus--update-meta)
                  (let ((history ttorus-history)
                        (ttorus (car (car ttorus-meta)))
                        (element)
                        (location-circle-torus))
                    (while (and (not location-circle-torus) history)
                      (setq element (pop history))
                      (when (not (equal ttorus (cddr element)))
                        (setq location-circle-torus element)))
                    (if location-circle-torus
                        (ttorus--meta-switch location-circle-torus)
                      (message "No alternate ttorus in history."))))
              (message "Meta History has less than two elements."))
          (ttorus--jump)))
    (message "Meta ttorus is empty.")))

;;;###autoload
(defun ttorus-alternate-circles ()
  "Alternate last two circles in history.
If outside the ttorus, just return inside, to the last ttorus location."
  (interactive)
  (if torus-cur-torus
      (progn
        (ttorus--prefix-argument-split current-prefix-arg)
        (if (ttorus--inside-p)
            (if (and ttorus-old-history
                     (>= (length ttorus-old-history) 2))
                (progn
                  (ttorus--update-meta)
                  (let ((history ttorus-old-history)
                        (circle (car (car torus-cur-torus)))
                        (element)
                        (location-circle))
                    (while (and (not location-circle) history)
                      (setq element (pop history))
                      (when (not (equal circle (cdr element)))
                        (setq location-circle element)))
                    (if location-circle
                        (ttorus--switch location-circle)
                      (message "No alternate circle in history."))))
              (message "History has less than two elements."))
          (ttorus--jump)))
    (message ttorus--message-empty-torus)))

;;;###autoload
(defun ttorus-alternate-menu (choice)
  "Alternate according to CHOICE."
  (interactive
   (list (read-key ttorus--message-alternate-choice)))
  (pcase choice
    (?m (funcall 'ttorus-alternate-in-meta))
    (?t (funcall 'ttorus-alternate-in-same-torus))
    (?c (funcall 'ttorus-alternate-in-same-circle))
    (?T (funcall 'ttorus-alternate-toruses))
    (?C (funcall 'ttorus-alternate-circles))
    (?\a (message "Alternate operation cancelled by Ctrl-G."))
    (_ (message "Invalid key."))))

;;; Rename
;;; ------------------------------

;;;###autoload
(defun ttorus-rename-circle ()
  "Rename current circle."
  (interactive)
  (if torus-cur-torus
      (let*
          ((old-name (car (car torus-cur-torus)))
           (prompt (format "New name of circle %s : " old-name))
           (circle-name (read-string prompt nil 'torus-minibuffer-history)))
        (ttorus--update-input-history circle-name)
        (setcar (car torus-cur-torus) circle-name)
        (dolist (location-circle ttorus-table)
          (when (equal (cdr location-circle) old-name)
            (setcdr location-circle circle-name)))
        (dolist (location-circle ttorus-old-history)
          (when (equal (cdr location-circle) old-name)
            (setcdr location-circle circle-name)))
        (dolist (location-circle-torus ttorus-history)
          (when (equal (cadr location-circle-torus) old-name)
            (setcar (cdr location-circle-torus) circle-name)))
        (dolist (location-circle-torus ttorus-index)
          (when (equal (cadr location-circle-torus) old-name)
            (setcar (cdr location-circle-torus) circle-name)))
        (message "Renamed circle %s -> %s" old-name circle-name))
    (message "ttorus is empty. Please add a circle first with ttorus-add-circle.")))

;;;###autoload
(defun ttorus-rename-torus ()
  "Rename current ttorus."
  (interactive)
  (if ttorus-meta
      (let*
          ((old-name (car (car ttorus-meta)))
           (prompt (format "New name of ttorus %s : " old-name))
           (ttorus-name (read-string prompt nil 'torus-minibuffer-history)))
        (ttorus--update-input-history ttorus-name)
        (setcar (car ttorus-meta) ttorus-name)
        (message "Renamed ttorus %s -> %s" old-name ttorus-name))
    (message ttorus--message-empty-lace)))

;;; Move
;;; ------------------------------

;;;###autoload
(defun ttorus-move-circle (circle-name)
  "Move current circle after CIRCLE-NAME."
  (interactive
   (list (completing-read
          "Move current circle after : "
          (mapcar #'car torus-cur-torus) nil t)))
  (ttorus--update-position)
  (let* ((circle (assoc circle-name torus-cur-torus))
         (index (1+ (cl-position circle torus-cur-torus :test #'equal)))
         (current (list (car torus-cur-torus)))
         (before (cl-subseq torus-cur-torus 1 index))
         (after (cl-subseq torus-cur-torus index)))
    (setq torus-cur-torus (append before current after))
    (ttorus-switch-circle (caar current))))

;;;###autoload
(defun ttorus-move-location (location-name)
  "Move current location after LOCATION-NAME."
  (interactive
   (list
    (completing-read
     "Move current location after : "
     (mapcar #'ttorus--concise (cdr (car torus-cur-torus))) nil t)))
  (ttorus--update-position)
  (let* ((circle (cdr (car torus-cur-torus)))
         (index (1+ (cl-position location-name circle
                                 :test #'ttorus--equal-concise-p)))
         (current (list (car circle)))
         (before (cl-subseq circle 1 index))
         (after (cl-subseq circle index)))
    (setcdr (car torus-cur-torus) (append before current after))
    (ttorus-switch-location (car current))))

;;;###autoload
(defun ttorus-move-torus (ttorus-name)
  "Move current ttorus after TTORUS-NAME."
  (interactive
   (list (completing-read
          "Move current ttorus after : "
          (mapcar #'car ttorus-meta) nil t)))
  (ttorus--update-meta)
  (let* ((ttorus (assoc ttorus-name ttorus-meta))
         (index (1+ (cl-position ttorus ttorus-meta :test #'equal)))
         (current (copy-lace (list (car ttorus-meta))))
         (before (copy-lace (cl-subseq ttorus-meta 1 index)))
         (after (copy-lace (cl-subseq ttorus-meta index))))
    (setq ttorus-meta (append before current after))
    (ttorus--update-from-meta)
    (ttorus-switch-torus (caar current))))

;;;###autoload
(defun ttorus-move-location-to-circle (circle-name)
  "Move current location to CIRCLE-NAME."
  (interactive
   (list (completing-read
          "Move current location to circle : "
          (mapcar #'car torus-cur-torus) nil t)))
  (ttorus--update-position)
  (let* ((location (car (cdr (car torus-cur-torus))))
         (circle (cdr (assoc circle-name torus-cur-torus)))
         (old-name (car (car torus-cur-torus)))
         (old-pair (cons location old-name)))
    (if (member location circle)
        (message "Location %s already exists in circle %s."
                 (ttorus--concise location)
                 circle-name)
      (message "Moving location %s to circle %s."
               (ttorus--concise location)
               circle-name)
      (pop (cdar torus-cur-torus))
      (setcdr (assoc circle-name torus-cur-torus)
              (push location circle))
      (dolist (location-circle ttorus-table)
        (when (equal location-circle old-pair)
          (setcdr location-circle circle-name)))
      (dolist (location-circle ttorus-old-history)
        (when (equal location-circle old-pair)
          (setcdr location-circle circle-name)))
      (ttorus--jump))))


;;;###autoload
(defun ttorus-move-circle-to-torus (ttorus-name)
  "Move current circle to TTORUS-NAME."
  (interactive
   (list (completing-read
          "Move current circle to ttorus : "
          (mapcar #'car ttorus-meta) nil t)))
  (ttorus--update-position)
  (let* ((circle (cl-copy-seq (car torus-cur-torus)))
         (ttorus (copy-lace
                 (cdr (assoc "ttorus" (assoc ttorus-name ttorus-meta)))))
         (circle-name (car circle))
         (circle-torus (cons circle-name (caar ttorus-meta))))
    (if (member circle ttorus)
        (message "Circle %s already exists in ttorus %s."
                 circle-name
                 ttorus-name)
      (message "Moving circle %s to ttorus %s."
               circle-name
               ttorus-name)
      (when (> ttorus-verbosity 2)
        (message "circle-torus %s" circle-torus))
      (setcdr (assoc "ttorus" (assoc ttorus-name ttorus-meta))
              (push circle ttorus))
      (setq torus-cur-torus (ttorus--assoc-delete-all circle-name torus-cur-torus))
      (setq ttorus-table
            (ttorus--reverse-assoc-delete-all circle-name ttorus-table))
      (setq ttorus-old-history
            (ttorus--reverse-assoc-delete-all circle-name ttorus-old-history))
      (setq ttorus-markers
            (ttorus--reverse-assoc-delete-all circle-name ttorus-markers))
      (setq ttorus-index
            (ttorus--reverse-assoc-delete-all circle-torus ttorus-index))
      (setq ttorus-history
            (ttorus--reverse-assoc-delete-all circle-torus ttorus-history))
      (ttorus--build-table)
      (setq ttorus-index (ttorus--build-index))
      (ttorus--jump))))

;;;###autoload
(defun ttorus-copy-location-to-circle (circle-name)
  "Copy current location to CIRCLE-NAME."
  (interactive
   (list (completing-read
          "Copy current location to circle : "
          (mapcar #'car torus-cur-torus) nil t)))
  (ttorus--update-position)
  (let* ((location (car (cdr (car torus-cur-torus))))
         (circle (cdr (assoc circle-name torus-cur-torus))))
    (if (member location circle)
        (message "Location %s already exists in circle %s."
                 (ttorus--concise location)
                 circle-name)
      (message "Copying location %s to circle %s."
                 (ttorus--concise location)
                 circle-name)
      (setcdr (assoc circle-name torus-cur-torus) (push location circle))
      (ttorus--build-table)
      (setq ttorus-index (ttorus--build-index)))))

;;;###autoload
(defun ttorus-copy-circle-to-torus (ttorus-name)
  "Copy current circle to TTORUS-NAME."
  (interactive
   (list (completing-read
          "Copy current circle to ttorus : "
          (mapcar #'car ttorus-meta) nil t)))
  (ttorus--update-position)
  (let* ((circle (cl-copy-seq (car torus-cur-torus)))
         (ttorus (copy-lace
                 (cdr (assoc "ttorus" (assoc ttorus-name ttorus-meta))))))
    (if (member circle ttorus)
        (message "Circle %s already exists in ttorus %s."
                 (car circle)
                 ttorus-name)
      (message "Copying circle %s to ttorus %s."
               (car circle)
               ttorus-name)
      (setcdr (assoc "ttorus" (assoc ttorus-name ttorus-meta))
              (push circle ttorus)))
    (ttorus--build-table)
    (setq ttorus-index (ttorus--build-index))))

;;; Reverse
;;; ------------------------------

;;;###autoload
(defun ttorus-reverse-circles ()
  "Reverse order of the circles."
  (interactive)
  (ttorus--update-position)
  (setq torus-cur-torus (reverse torus-cur-torus))
  (ttorus--jump))

;;;###autoload
(defun ttorus-reverse-locations ()
  "Reverse order of the locations in the current circles."
  (interactive)
  (ttorus--update-position)
  (setcdr (car torus-cur-torus) (reverse (cdr (car torus-cur-torus))))
  (ttorus--jump))

;;;###autoload
(defun ttorus-deep-reverse ()
  "Reverse order of the locations in each circle."
  (interactive)
  (ttorus--update-position)
  (setq torus-cur-torus (reverse torus-cur-torus))
  (dolist (circle torus-cur-torus)
    (setcdr circle (reverse (cdr circle))))
  (ttorus--jump))


;;;###autoload
(defun ttorus-reverse-menu (choice)
  "Split according to CHOICE."
  (interactive
   (list (read-key ttorus--message-reverse-choice)))
  (pcase choice
    (?c (funcall 'ttorus-reverse-circles))
    (?l (funcall 'ttorus-reverse-locations))
    (?d (funcall 'ttorus-deep-reverse))
    (?\a (message "Reverse operation cancelled by Ctrl-G."))
    (_ (message "Invalid key."))))

;;; Join
;;; ------------------------------

;;;###autoload
(defun ttorus-prefix-circles-of-current-torus (prefix)
  "Add PREFIX to circle names of `torus-cur-torus'."
  (interactive
   (list
    (read-string (format ttorus--message-prefix-circle
                         (car (car ttorus-meta)))
                 nil
                 'torus-minibuffer-history)))
  (let ((varlist))
    (setq varlist (ttorus--prefix-circles prefix (car (car ttorus-meta))))
    (setq torus-cur-torus (car varlist))
    (setq ttorus-old-history (car (cdr varlist))))
  (ttorus--build-table)
  (setq ttorus-index (ttorus--build-index)))

;;;###autoload
(defun ttorus-join-circles (circle-name)
  "Join current circle with CIRCLE-NAME."
  (interactive
   (list
    (completing-read "Join current circle with circle : "
                     (mapcar #'car torus-cur-torus) nil t)))
  (let* ((current-name (car (car torus-cur-torus)))
         (join-name (concat current-name ttorus-join-separator circle-name))
         (user-choice
          (read-string (format "Name of the joined ttorus [%s] : " join-name))))
    (when (> (length user-choice) 0)
      (setq join-name user-choice))
    (ttorus-add-circle join-name)
    (setcdr (car torus-cur-torus)
            (append (cdr (assoc current-name torus-cur-torus))
                    (cdr (assoc circle-name torus-cur-torus))))
    (delete-dups (cdr (car torus-cur-torus))))
  (ttorus--update-meta)
  (ttorus--build-table)
  (setq ttorus-index (ttorus--build-index))
  (ttorus--jump))

;;;###autoload
(defun ttorus-join-toruses (ttorus-name)
  "Join current ttorus with TTORUS-NAME in `ttorus-meta'."
  (interactive
   (list
    (completing-read "Join current ttorus with ttorus : "
                     (mapcar #'car ttorus-meta) nil t)))
  (ttorus--prefix-argument-split current-prefix-arg)
  (ttorus--update-meta)
  (let* ((current-name (car (car ttorus-meta)))
         (join-name (concat current-name ttorus-join-separator ttorus-name))
         (user-choice
          (read-string (format "Name of the joined ttorus [%s] : " join-name)))
         (prompt-current
          (format ttorus--message-prefix-circle current-name))
         (prompt-added
          (format ttorus--message-prefix-circle ttorus-name))
         (prefix-current
          (read-string prompt-current nil 'torus-minibuffer-history))
         (prefix-added
          (read-string prompt-added nil 'torus-minibuffer-history))
         (varlist)
         (ttorus-added)
         (history-added)
         (input-added))
    (when (> (length user-choice) 0)
      (setq join-name user-choice))
    (ttorus--update-input-history prefix-current)
    (ttorus--update-input-history prefix-added)
    (ttorus-add-copy-of-torus join-name)
    (ttorus-prefix-circles-of-current-torus prefix-current)
    (setq varlist (ttorus--prefix-circles prefix-added ttorus-name))
    (setq ttorus-added (car varlist))
    (setq history-added (car (cdr varlist)))
    (setq input-added (car (cdr (cdr varlist))))
    (if (seq-intersection torus-cur-torus ttorus-added #'ttorus--equal-car-p)
        (message ttorus--message-circle-name-collision)
      (setq torus-cur-torus (append torus-cur-torus ttorus-added))
      (setq ttorus-old-history (append ttorus-old-history history-added))
      (setq torus-minibuffer-history (append torus-minibuffer-history input-added))))
  (ttorus--update-meta)
  (ttorus--build-table)
  (setq ttorus-index (ttorus--build-index))
  (ttorus--jump))

;;; Autogroup
;;; ------------------------------

;;;###autoload
(defun ttorus-autogroup (quoted-function)
  "Autogroup all ttorus locations according to the values of QUOTED-FUNCTION.
A new ttorus is created on `ttorus-meta' to contain the new circles.
The function must return the names of the new circles as strings."
  (interactive)
  (let ((ttorus-name
         (read-string "Name of the autogroup ttorus : "
                      nil
                      'torus-minibuffer-history))
        (all-locations))
    (if (assoc ttorus-name ttorus-meta)
        (message "ttorus %s already exists in ttorus-meta" ttorus-name)
      (ttorus-add-copy-of-torus ttorus-name)
      (dolist (circle torus-cur-torus)
        (dolist (location (cdr circle))
          (push location all-locations)))
      (setq torus-cur-torus (seq-group-by quoted-function all-locations))))
  (setq ttorus-old-history nil)
  (setq ttorus-markers nil)
  (setq torus-minibuffer-history nil)
  (ttorus--build-table)
  (setq ttorus-index (ttorus--build-index))
  (ttorus--update-meta)
  (ttorus--jump))

;;;###autoload
(defun ttorus-autogroup-by-path ()
  "Autogroup all location of the ttorus by directories.
A new ttorus is created to contain the new circles."
  (interactive)
  (ttorus-autogroup (lambda (elem) (directory-file-name (file-name-directory (car elem))))))

;;;###autoload
(defun ttorus-autogroup-by-directory ()
  "Autogroup all location of the ttorus by directories.
A new ttorus is created to contain the new circles."
  (interactive)
  (ttorus-autogroup #'ttorus--directory))

;;;###autoload
(defun ttorus-autogroup-by-extension ()
  "Autogroup all location of the ttorus by extension.
A new ttorus is created to contain the new circles."
  (interactive)
  (ttorus-autogroup #'ttorus--extension-description))

;;;###autoload
(defun ttorus-autogroup-by-git-repo ()
  "Autogroup all location of the ttorus by git repositories.
A new ttorus is created to contain the new circles."
  ;; TODO
  )

;;;###autoload
(defun ttorus-autogroup-menu (choice)
  "Autogroup according to CHOICE."
  (interactive
   (list (read-key ttorus--message-autogroup-choice)))
    (pcase choice
      (?p (funcall 'ttorus-autogroup-by-path))
      (?d (funcall 'ttorus-autogroup-by-directory))
      (?e (funcall 'ttorus-autogroup-by-extension))
      (?\a (message "Autogroup cancelled by Ctrl-G."))
      (_ (message "Invalid key."))))

;;; Batch
;;; ------------------------------


;;;###autoload
(defun ttorus-run-elisp-code-on-circle (elisp-code)
  "Run ELISP-CODE to all files of the circle."
  (interactive (list (read-string
                      "Elisp code to run to all files of the circle : ")))
  (dolist (iter (number-sequence 1 (length (cdar torus-cur-torus))))
    (when (> ttorus-verbosity 1)
      (message "%d. Applying %s to %s" iter elisp-code (cadar torus-cur-torus))
      (message "Evaluated : %s"
               (car (read-from-string (format "(progn %s)" elisp-code)))))
    (ttorus--eval-string elisp-code)
    (ttorus-next-location)))

;;;###autoload
(defun ttorus-run-elisp-command-on-circle (command)
  "Run an Emacs Lisp COMMAND to all files of the circle."
  (interactive (list (read-command
                      "Elisp command to run to all files of the circle : ")))
  (dolist (iter (number-sequence 1 (length (cdar torus-cur-torus))))
    (when (> ttorus-verbosity 1)
      (message "%d. Applying %s to %s" iter command (cadar torus-cur-torus)))
    (funcall command)
    (ttorus-next-location)))

;;;###autoload
(defun ttorus-run-shell-command-on-circle (command)
  "Run a shell COMMAND to all files of the circle."
  (interactive (list (read-string
                      "Shell command to run to all files of the circle : ")))
  (let ((keep-value shell-command-dont-erase-buffer))
    (setq shell-command-dont-erase-buffer t)
    (dolist (iter (number-sequence 1 (length (cdar torus-cur-torus))))
      (when (> ttorus-verbosity 1)
        (message "%d. Applying %s to %s" iter command (cadar torus-cur-torus)))
      (shell-command (format "%s %s"
                             command
                             (shell-quote-argument (buffer-file-name))))
      (ttorus-next-location))
    (setq shell-command-dont-erase-buffer keep-value)))

;;;###autoload
(defun ttorus-run-async-shell-command-on-circle (command)
  "Run a shell COMMAND to all files of the circle."
  (interactive (list (read-string
                      "Shell command to run to all files of the circle : ")))
  (let ((keep-value async-shell-command-buffer))
    (setq async-shell-command-buffer 'new-buffer)
    (dolist (iter (number-sequence 1 (length (cdar torus-cur-torus))))
      (when (> ttorus-verbosity 1)
        (message "%d. Applying %s to %s" iter command (cadar torus-cur-torus)))
      (async-shell-command (format "%s %s"
                             command
                             (shell-quote-argument (buffer-file-name))))
      (ttorus-next-location))
    (setq async-shell-command-buffer keep-value)))

;;;###autoload
(defun ttorus-batch-menu (choice)
  "Split according to CHOICE."
  (interactive
   (list (read-key ttorus--message-batch-choice)))
  (pcase choice
    (?e (call-interactively 'ttorus-run-elisp-code-on-circle))
    (?c (call-interactively 'ttorus-run-elisp-command-on-circle))
    (?! (call-interactively 'ttorus-run-shell-command-on-circle))
    (?& (call-interactively 'ttorus-run-async-shell-command-on-circle))
    (?\a (message "Batch operation cancelled by Ctrl-G."))
    (_ (message "Invalid key."))))

;;; Split
;;; ------------------------------

;;;###autoload
(defun ttorus-split-horizontally ()
  "Split horizontally to view all buffers in current circle.
Split until `ttorus-maximum-horizontal-split' is reached."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (numsplit (1- (length circle))))
    (when (> ttorus-verbosity 1)
      (message "numsplit = %d" numsplit))
    (if (> numsplit (1- ttorus-maximum-horizontal-split))
        (message "Too many files to split.")
      (delete-other-windows)
      (dolist (iter (number-sequence 1 numsplit))
        (when (> ttorus-verbosity 2)
          (message "iter = %d" iter))
        (split-window-below)
        (balance-windows)
        (other-window 1)
        (ttorus-next-location))
      (other-window 1)
      (ttorus-next-location))))

;;;###autoload
(defun ttorus-split-vertically ()
  "Split vertically to view all buffers in current circle.
Split until `ttorus-maximum-vertical-split' is reached."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (numsplit (1- (length circle))))
    (when (> ttorus-verbosity 1)
      (message "numsplit = %d" numsplit))
    (if (> numsplit (1- ttorus-maximum-vertical-split))
        (message "Too many files to split.")
      (delete-other-windows)
      (dolist (iter (number-sequence 1 numsplit))
        (when (> ttorus-verbosity 2)
          (message "iter = %d" iter))
        (split-window-right)
        (balance-windows)
        (other-window 1)
        (ttorus-next-location))
      (other-window 1)
      (ttorus-next-location))))

;;;###autoload
(defun ttorus-split-main-left ()
  "Split with left main window to view all buffers in current circle."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (numsplit (- (length circle) 2)))
    (when (> ttorus-verbosity 1)
      (message "numsplit = %d" numsplit))
    (if (> numsplit (1- ttorus-maximum-horizontal-split))
        (message "Too many files to split.")
      (delete-other-windows)
      (split-window-right)
      (other-window 1)
      (ttorus-next-location)
      (dolist (iter (number-sequence 1 numsplit))
        (when (> ttorus-verbosity 2)
          (message "iter = %d" iter))
        (split-window-below)
        (balance-windows)
        (other-window 1)
        (ttorus-next-location))
      (other-window 1)
      (ttorus-next-location))))

;;;###autoload
(defun ttorus-split-main-right ()
  "Split with right main window to view all buffers in current circle."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (numsplit (- (length circle) 2)))
    (when (> ttorus-verbosity 1)
      (message "numsplit = %d" numsplit))
    (if (> numsplit (1- ttorus-maximum-horizontal-split))
        (message "Too many files to split.")
      (delete-other-windows)
      (split-window-right)
      (ttorus-next-location)
      (dolist (iter (number-sequence 1 numsplit))
        (when (> ttorus-verbosity 2)
          (message "iter = %d" iter))
        (split-window-below)
        (balance-windows)
        (other-window 1)
        (ttorus-next-location))
      (other-window 1)
      (ttorus-next-location))))

;;;###autoload
(defun ttorus-split-main-top ()
  "Split with main top window to view all buffers in current circle."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (numsplit (- (length circle) 2)))
    (when (> ttorus-verbosity 1)
      (message "numsplit = %d" numsplit))
    (if (> numsplit (1- ttorus-maximum-vertical-split))
        (message "Too many files to split.")
      (delete-other-windows)
      (split-window-below)
      (other-window 1)
      (ttorus-next-location)
      (dolist (iter (number-sequence 1 numsplit))
        (when (> ttorus-verbosity 2)
          (message "iter = %d" iter))
        (split-window-right)
        (balance-windows)
        (other-window 1)
        (ttorus-next-location))
      (other-window 1)
      (ttorus-next-location))))

;;;###autoload
(defun ttorus-split-main-bottom ()
  "Split with main bottom window to view all buffers in current circle."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (numsplit (- (length circle) 2)))
    (when (> ttorus-verbosity 1)
      (message "numsplit = %d" numsplit))
    (if (> numsplit (1- ttorus-maximum-vertical-split))
        (message "Too many files to split.")
      (delete-other-windows)
      (split-window-below)
      (ttorus-next-location)
      (dolist (iter (number-sequence 1 numsplit))
        (when (> ttorus-verbosity 2)
          (message "iter = %d" iter))
        (split-window-right)
        (balance-windows)
        (other-window 1)
        (ttorus-next-location))
      (other-window 1)
      (ttorus-next-location))))

;;;###autoload
(defun ttorus-split-grid ()
  "Split horizontally & vertically to view all current circle buffers in a grid."
  (interactive)
  (let* ((circle (cdr (car torus-cur-torus)))
         (len-circle (length circle))
         (max-iter (1- len-circle))
         (ratio (/ (float (frame-text-width))
                   (float (frame-text-height))))
         (horizontal (sqrt (/ (float len-circle) ratio)))
         (vertical (* ratio horizontal))
         (int-hor (min (ceiling horizontal)
                       ttorus-maximum-horizontal-split))
         (int-ver (min (ceiling vertical)
                       ttorus-maximum-vertical-split))
         (getout)
         (num-hor-minus)
         (num-hor)
         (num-ver-minus)
         (total 0))
    (if (< (* int-hor int-ver) len-circle)
        (message "Too many files to split.")
      (let ((dist-dec-hor)
            (dist-dec-ver))
        (when (> ttorus-verbosity 2)
          (message "ratio = %f" ratio)
          (message "horizontal = %f" horizontal)
          (message "vertical = %f" vertical)
          (message "int-hor int-ver = %d %d" int-hor  int-ver))
        (while (not getout)
          (setq dist-dec-hor (abs (- (* (1- int-hor) int-ver) len-circle)))
          (setq dist-dec-ver (abs (- (* int-hor (1- int-ver)) len-circle)))
          (when (> ttorus-verbosity 2)
            (message "Distance hor ver = %f %f" dist-dec-hor dist-dec-ver))
          (cond ((and (<= dist-dec-hor dist-dec-ver)
                      (>= (* (1- int-hor) int-ver) len-circle))
                 (setq int-hor (1- int-hor))
                 (when (> ttorus-verbosity 2)
                   (message "Decrease int-hor : int-hor int-ver = %d %d"
                            int-hor  int-ver)))
                ((and (>= dist-dec-hor dist-dec-ver)
                      (>= (* int-hor (1- int-ver)) len-circle))
                 (setq int-ver (1- int-ver))
                 (when (> ttorus-verbosity 2)
                   (message "Decrease int-ver : int-hor int-ver = %d %d"
                            int-hor  int-ver)))
                (t (setq getout t)
                   (when (> ttorus-verbosity 2)
                     (message "Getout : %s" getout)
                     (message "int-hor int-ver = %d %d" int-hor int-ver))))))
      (setq num-hor-minus (number-sequence 1 (1- int-hor)))
      (setq num-hor (number-sequence 1 int-hor))
      (setq num-ver-minus (number-sequence 1 (1- int-ver)))
      (when (> ttorus-verbosity 2)
        (message "num-hor-minus = %s" num-hor-minus)
        (message "num-hor = %s" num-hor)
        (message "num-ver-minus = %s" num-ver-minus))
      (delete-other-windows)
      (dolist (iter-hor num-hor-minus)
        (when (> ttorus-verbosity 2)
          (message "iter hor = %d" iter-hor))
        (setq max-iter (1- max-iter))
        (split-window-below)
        (balance-windows)
        (other-window 1))
      (other-window 1)
      (dolist (iter-hor num-hor)
        (dolist (iter-ver num-ver-minus)
          (when (> ttorus-verbosity 2)
            (message "iter hor ver = %d %d" iter-hor iter-ver)
            (message "total max-iter = %d %d" total max-iter))
          (when (< total max-iter)
            (setq total (1+ total))
            (split-window-right)
            (balance-windows)
            (other-window 1)
            (ttorus-next-location)))
        (when (< total max-iter)
          (other-window 1)
          (ttorus-next-location)))
    (other-window 1)
    (ttorus-next-location))))

;;;###autoload
(defun ttorus-layout-menu (choice)
  "Split according to CHOICE."
  (interactive
   (list (read-key ttorus--message-layout-choice)))
  (ttorus--complete-and-clean-layout)
  (let ((circle (caar torus-cur-torus)))
    (when (member choice '(?m ?o ?h ?v ?l ?r ?t ?b ?g))
      (setcdr (assoc circle ttorus-layout) choice))
    (pcase choice
      (?m nil)
      (?o (delete-other-windows))
      (?h (funcall 'ttorus-split-horizontally))
      (?v (funcall 'ttorus-split-vertically))
      (?l (funcall 'ttorus-split-main-left))
      (?r (funcall 'ttorus-split-main-right))
      (?t (funcall 'ttorus-split-main-top))
      (?b (funcall 'ttorus-split-main-bottom))
      (?g (funcall 'ttorus-split-grid))
      (?\a (message "Layout cancelled by Ctrl-G."))
      (_ (message "Invalid key.")))))

;;; Tabs
;;; ------------------------------

(defun ttorus-tab-mouse (event)
  "Manage click EVENT on locations part of tab line."
  (interactive "@e")
  (let* ((index (cdar (nthcdr 4 (cadr event))))
        (before (substring-no-properties
                    (caar (nthcdr 4 (cadr event))) 0 index))
        (pipes (seq-filter (lambda (elem) (equal elem ?|)) before))
        (len-pipes (length pipes)))
    (if (equal len-pipes 0)
        (ttorus-alternate-in-same-circle)
      (ttorus-switch-location (nth (length pipes) (cdar torus-cur-torus))))))

;;; Delete
;;; ------------------------------

;;;###autoload
(defun ttorus-delete-circle (circle-name)
  "Delete circle given by CIRCLE-NAME."
  (interactive
   (list
    (completing-read "Delete circle : "
                     (mapcar #'car torus-cur-torus) nil t)))
  (when (y-or-n-p (format "Delete circle %s ? " circle-name))
    (setq torus-cur-torus (ttorus--assoc-delete-all circle-name torus-cur-torus))
    (setq ttorus-table
          (ttorus--reverse-assoc-delete-all circle-name ttorus-table))
    (setq ttorus-old-history
          (ttorus--reverse-assoc-delete-all circle-name ttorus-old-history))
    (setq ttorus-markers
          (ttorus--reverse-assoc-delete-all circle-name ttorus-markers))
    (let ((circle-torus (cons (caar torus-cur-torus) (caar ttorus-meta))))
      (setq ttorus-index
            (ttorus--reverse-assoc-delete-all circle-torus ttorus-index))
      (setq ttorus-history
            (ttorus--reverse-assoc-delete-all circle-torus ttorus-history)))
    (ttorus--build-table)
    (setq ttorus-index (ttorus--build-index))
    (ttorus--jump)))

;;;###autoload
(defun ttorus-delete-location (location-name)
  "Delete location given by LOCATION-NAME."
  (interactive
   (list
    (completing-read
     "Delete location : "
     (mapcar #'ttorus--concise (cdr (car torus-cur-torus))) nil t)))
  (if (and
       (> (length (car torus-cur-torus)) 1)
       (y-or-n-p
        (format
         "Delete %s from circle %s ? "
         location-name
         (car (car torus-cur-torus)))))
      (let* ((circle (cdr (car torus-cur-torus)))
             (index (cl-position location-name circle
                                 :test #'ttorus--equal-concise-p))
             (location (nth index circle))
             (location-circle (cons location (caar torus-cur-torus)))
             (location-circle-torus (cons location (cons (caar torus-cur-torus)
                                                         (caar ttorus-meta)))))
        (setcdr (car torus-cur-torus) (cl-remove location circle))
        (setq ttorus-table (cl-remove location-circle ttorus-table))
        (setq ttorus-old-history (cl-remove location-circle ttorus-old-history))
        (setq ttorus-markers (cl-remove location-circle ttorus-markers))
        (setq ttorus-index (cl-remove location-circle-torus ttorus-index))
        (setq ttorus-history (cl-remove location-circle-torus ttorus-history))
        (ttorus--jump))
    (message "No location in current circle.")))

;;;###autoload
(defun ttorus-delete-current-circle ()
  "Delete current circle."
  (interactive)
  (ttorus-delete-circle (ttorus--concise (car (car torus-cur-torus)))))

;;;###autoload
(defun ttorus-delete-current-location ()
  "Remove current location from current circle."
  (interactive)
  (ttorus-delete-location (ttorus--concise (car (cdr (car torus-cur-torus))))))

;;;###autoload
(defun ttorus-delete-torus (ttorus-name)
  "Delete ttorus given by TTORUS-NAME."
  (interactive
   (list
    (completing-read "Delete ttorus : "
                     (mapcar #'car ttorus-meta) nil t)))
  (when (y-or-n-p (format "Delete ttorus %s ? " ttorus-name))
    (when (equal ttorus-name (car (car ttorus-meta)))
      (ttorus-switch-torus (car (car (cdr ttorus-meta)))))
    (setq ttorus-meta (ttorus--assoc-delete-all ttorus-name ttorus-meta))))

;;; File R/W
;;; ------------------------------

;;;###autoload
(defun ttorus-read (filename)
  "Read main ttorus variables from FILENAME as Lisp code."
  (interactive
   (list
    (read-file-name
     "ttorus file : "
     (file-name-as-directory ttorus-dirname))))
  (let*
      ((file-basename (file-name-nondirectory filename))
       (minus-len-ext (- (min (length torus-file-extension)
                              (length filename))))
       (buffer))
    (unless (equal (cl-subseq filename minus-len-ext) torus-file-extension)
      (setq filename (concat filename torus-file-extension)))
    (when (or (not torus-lace)
              (y-or-n-p ttorus--message-replace-torus))
      (ttorus--update-input-history file-basename)
      (if (file-exists-p filename)
          (progn
            (setq buffer (find-file-noselect filename))
            (eval-buffer buffer)
            (kill-buffer buffer))
        (message "File %s does not exist." filename))))
  (ttorus--convert-old-vars)
  (ttorus--jump))

;;;###autoload
(defun ttorus-write (filename)
  "Write main ttorus variables to FILENAME as Lisp code.
An adequate extension is added if needed.
If called interactively, ask for the variables to save (default : all)."
  (interactive
   (list
    (read-file-name
     "ttorus file : "
     (file-name-as-directory ttorus-dirname))))
  ;; We surely don’t want to load a file we’ve just written
  (remove-hook 'after-save-hook 'ttorus-after-save-torus-file)
  (if ttorus-meta
      (let*
          ((file-basename (file-name-nondirectory filename))
           (minus-len-ext (- (min (length torus-file-extension)
                                  (length filename))))
           (buffer)
           (varlist '(torus-lace
                      ttorus-index
                      ttorus-history
                      torus-minibuffer-history
                      ttorus-layout
                      ttorus-line-col)))
        (ttorus--update-position)
        (ttorus--update-input-history file-basename)
        (unless (equal (cl-subseq filename minus-len-ext) torus-file-extension)
          (setq filename (concat filename torus-file-extension)))
        (unless ttorus-table
          (ttorus--build-table))
        (unless ttorus-index
          (setq ttorus-index (ttorus--build-index)))
        (ttorus--complete-and-clean-layout)
        (ttorus--update-meta)
        (if varlist
            (progn
              (ttorus--roll-backups filename)
              (setq buffer (find-file-noselect filename))
              (with-current-buffer buffer
                (erase-buffer)
                (dolist (var varlist)
                  (when var
                    (insert (concat
                             "(setq "
                             (symbol-name var)
                             " (quote\n"))
                    (pp (symbol-value var) buffer)
                    (insert "))\n\n")))
                (save-buffer)
                (kill-buffer)))
          (message "Write cancelled : empty variables.")))
    (message "Write cancelled : empty ttorus."))
  ;; Restore the hook
  (add-hook 'after-save-hook 'ttorus-after-save-torus-file))

;;;###autoload
(defun ttorus-edit (filename)
  "Edit ttorus file FILENAME in the ttorus files dir.
Be sure to understand what you’re doing, and not leave some variables
in inconsistent state, or you might encounter strange undesired effects."
  (interactive
   (list
    (read-file-name
     "ttorus file : "
     (file-name-as-directory ttorus-dirname))))
  (find-file filename))

;;; End
;;; ------------------------------------------------------------

(provide 'ttorus)

;; Local Variables:
;; mode: emacs-lisp
;; indent-tabs-mode: nil
;; End:

;;; ttorus.el ends here
