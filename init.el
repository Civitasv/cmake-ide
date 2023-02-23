;;; basic/cpp/cmake/init.el -*- lexical-binding: t; -*-
;;; --- Calls CMake to find out include paths and other compiler flags

;; Copyright (C) 2023 Civitasv

;; Author:  Civitasv <hscivitasv@gmail.com>
;; Version: 0.6
;; Package-Requires: ((emacs "28.0"))
;; Keywords: languages
;; URL: http://github.com/Civitasv/cmake-tools

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This package runs CMake and sets variables for IDE-like functionality
;; provided by other packages such as:
;; On the fly syntax checks with flycheck
;; auto-completion using auto-complete-clang or company-clang
;; Jump to definition and refactoring with rtags
;; These other packages must be installed for the functionality to work

;;; Usage:

;; (cmake-tools-setup)
;;
;; If cmake-tools-flags-c or cmake-ide-flags-c++ are set, they will be added to ac-clang-flags.
;; These variables should be set. Particularly, they should contain the system include paths.
;;
;;; Code:

(require 'json)
(require 'find-file)
(require 'cl-lib)
(require 'seq)
(require 's)
(require 'dash)

(defcustom cmake-tools-command
  "cmake"
  "The cmake command"
  :group 'cmake-tools
  :type 'string)

(defcustom cmake-tools-build-directory
  "build"
  "The build directory to run CMake in.  Default to be =build=."
  :group 'cmake-tools
  :type 'directory
  :safe #'stringp)

(defcustom cmake-tools-generate-options
  '("-DCMAKE_EXPORT_COMPILE_COMMANDS=1")
  "List of options passed to cmake when generating."
  :group 'cmake-tools
  :type '(repeat string)
  :safe (lambda (val) (and (listp val) (-all-p 'stringp val))))

(defcustom cmake-tools-build-options
  ()
  "List of options passwd to cmake when building target."
  :group 'cmake-tools
  :type '(repeat string)
  :safe (lambda (val) (and (listp val) (-all-p 'stringp val))))

(defcustom cmake-tools-identify-extensions
  '(".c" ".cpp" ".C" ".cxx" ".cc" ".h" ".hpp")
  "A list of file extensions that qualify as source files."
  :group 'cmake-tools
  :type '(repeat string))

(defun cmake-tools-can-identify (name)
  "Test if cmake can identify NAME"
  (cl-some (lambda (x) (string-suffix-p x name)) cmake-tools-src-extensions))

(defun cmake-tools-mode-hook()
  "Function to add to a major mode hook"
  (add-hook 'find-file-hook #'cmake-tools-maybe-run-cmake nil 'local)
  (cmake-tools-maybe-start-rdm))

;;;###autoload
(defun cmake-tools-setup ()
  "Set up the Emacs hooks for working with CMake projects."
  (add-hook 'c-mode-hook #'cmake-tools-mode-hook)
  (add-hook 'c++-mode-hook #'cmake-tools-mode-hook)

  ;; When creating a file in Emacs, run CMake again to pick it up
  (add-hook 'before-save-hook #'cmake-tools-before-save))

(defun cmake-tools-before-save ()
  "When creating a file in Emacs, run CMake again to pick it up."
  (when (and (cmake-tools-can-identify (buffer-file-name))
             (not (file-readable-p (buffer-file-name))))
    (add-hook 'after-save-hook 'cmake-tools-new-file-saved nil 'local)))

(defun cmake-tools-new-file-saved ()
  "Run CMake to pick up newly created files."
  (cmake-tools-run-cmake)
  (remove-hook 'after-save-hook 'cmake-tools-new-file-saved 'local))

(defun cmake-tools-generate ()
  (interactive)
  (when (not (cmake-tools-utils-has-active-process))
    (let ((configuration (cmake-tools-utils-get-cmake-configuration)))
      (if (not (= (cmake-tools-get-identifier-from-result configuration) CMAKE-TOOLS-SUCCESS))
          (cmake-tools-utils-message (cmake-tools-get-message-from-result configuration))
        (let ((build-type (cmake-tools-config-get-build-type)))
          ;; first, select build type
          (when (not build-type)
            (cmake-tools-select-build-type))
          ;; then, set build dir
          (cmake-tools-config-update-build-dir cmake-tools-build-directory)
          ;; then, generate build dir
          (cmake-tools-config-generate-build-dir)
          ;; then, run cmake configure command
          (apply 'start-process
                 (append (list "cmake" "*cmake-tools*" "cmake")
                         (list "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
                               "-B" (cmake-tools-config-get-build-dir)
                               "-S" "."
                               "-D" "CMAKE_BUILD_TYPE=" (cmake-tools-config-get-build-type)))))))))

(defun cmake-tools-clean())

(defun cmake-tools-build ())

(defun cmake-tools-stop ())

(defun cmake-tools-install ())

(defun cmake-tools-run ())

(defun cmake-tools-debug ())

(defun cmake-tools-select-build-type ()
  (interactive)
  (when (not (cmake-tools-utils-has-active-process))
    (let ((choices '("Debug" "Release" "RelWithDebInfo" "MinSizeRel")))
      (cmake-tools-config-set-build-type (completing-read "Select Build Type: " choices )))))

(defun cmake-tools-select-build-target ())

(defun cmake-tools-select-launch-target ())

;;; result, uniform return
(defun cmake-tools-make-a-result (identifier data message)
  (list identifier data message))
(defun cmake-tools-get-identifier-from-result (result)
  (car result))
(defun cmake-tools-get-data-from-result (result)
  (cadr result))
(defun cmake-tools-get-message-from-result (result)
  (caddr result))

;;; code, identifier
(defconst CMAKE-TOOLS-SUCCESS 1 "means success")
(defconst CMAKE-TOOLS-NOT-CONFIGURED 2 "means success")
(defconst CMAKE-TOOLS-NOT-SELECT-LAUNCH-TARGET 3 "means success")
(defconst CMAKE-TOOLS-SELECTED-LAUNCH-TARGET-NOT-BUILT 4 "means success")
(defconst CMAKE-TOOLS-NOT-A-LAUNCH-TARGET 5 "means success")
(defconst CMAKE-TOOLS-NOT-EXECUTABLE 6 "means success")
(defconst CMAKE-TOOLS-CANNOT-FIND-CMAKE-CONFIGURATION-FILE 7 "means success")
(defconst CMAKE-TOOLS-CANNOT-FIND-CODEMODEL-FILE 8 "means success")
(defconst CMAKE-TOOLS-CANNOT-CREATE-CODEMODEL-QUERY-FILE 9 "means success")
(defconst CMAKE-TOOLS-CANNOT-DEBUG-LAUNCH-TARGET 10 "means success")
(defconst CMAKE-TOOLS-CANNOT-CREATE-DIRECTORY 11 "means success")

;;; config
(defvar cmake-tools-config-instance
  '(nil ;; build directory
    nil ;; query directory
    nil ;; reply directory
    nil ;; generate options
    nil ;; build options
    nil ;; build type
    nil ;; build target
    nil ;; launch target
    ))

(defun cmake-tools-config-set-build-dir (build-dir)
  (setcar cmake-tools-config-instance build-dir))
(defun cmake-tools-config-set-query-dir (query-dir)
  (setcar (cdr cmake-tools-config-instance) query-dir))
(defun cmake-tools-config-set-reply-dir (reply-dir)
  (setcar (cddr cmake-tools-config-instance) reply-dir))
(defun cmake-tools-config-set-build-type (build-type)
  (setcar (cdr (cddddr cmake-tools-config-instance)) build-type))

(defun cmake-tools-config-get-build-dir ()
  (car cmake-tools-config-instance))
(defun cmake-tools-config-get-query-dir ()
  (cadr cmake-tools-config-instance))
(defun cmake-tools-config-get-reply-dir ()
  (caddr cmake-tools-config-instance))
(defun cmake-tools-config-get-generate-opt ()
  (cadddr cmake-tools-config-instance))
(defun cmake-tools-config-get-build-opt ()
  (car (cddddr cmake-tools-config-instance)))
(defun cmake-tools-config-get-build-type ()
  (car (cdr (cddddr cmake-tools-config-instance))))

(defun cmake-tools-config-update-build-dir (build-dir)
  (cmake-tools-config-set-build-dir build-dir)
  (cmake-tools-config-set-query-dir (s-concat build-dir "/.cmake" "/api" "/v1" "/query"))
  (cmake-tools-config-set-reply-dir (s-concat build-dir "/.cmake" "/api" "/v1" "/reply")))

(defun cmake-tools-config-generate-build-dir ()
  (if (not (file-exists-p (cmake-tools-config-get-build-dir)))
      (progn (make-directory (cmake-tools-config-get-build-dir) 'parents)
             (cmake-tools-config-generate-query-file))))

(defun cmake-tools-config-generate-query-file ()
  (if (not (file-exists-p (cmake-tools-config-get-query-dir)))
      (progn (make-directory (cmake-tools-config-get-query-dir) 'parents)
             (make-empty-file (s-concat (cmake-tools-config-get-query-dir) "/codemodel-v2")))))

(defun cmake-tools-config-get-codemodel-targets ()
  ;; first, check if reply directory exists
  (if (not (file-exists-p (cmake-tools-config-get-reply-dir)))
      (cmake-tools-utils-message "还没有 Configure 哦～")
    ;; then, search file with pattern codemodel*
    (let ((file (file-expand-wildcards (s-concat (cmake-tools-config-get-reply-dir) "codemodel*"))))
      (if (not file)
          (cmake-tools-utils-message "找不到 codemodel file 呢～")
        (let ((codemodel (car file)))
          ;; parse it, using json library
          (let ((codemodel_json (json-read-file codemodel)))
            (gethash "targets" (car (gethash "configurations" codemodel_json)))))))))

(defun cmake-tools-config-get-codemodel-target-info (codemodel_target)
  (let ((result (json-read-file (s-concat (cmake-tools-config-get-reply-dir) (gethash "jsonFile" codemodel_target)))))
    result))

(defun cmake-tools-config-check-launch-target ()
  ;; 1. if not configured
  (if (not (file-exists-p (cmake-tools-config-get-build-dir)))
      (cmake-tools-utils-message "还没有 Configure 哦～")
    ;; 2. check if has selected launch target
    (if (not (cmake-tools-config-get-launch-target))
        (cmake-tools-utils-message "还没有选择 launch target 哦")
      (let ((target (cmake-tools-config-get-codemodel-targets)))
        target))))

(defun cmake-tools-config-get-cwd ()
  default-directory)

;;; utils
(defun cmake-tools-utils-has-active-process ()
  "查看当前是否已经存在 CMake 进程"
  (get-process "cmake"))

(defun cmake-tools-utils-message (str &rest vars)
  "Output a message with STR and formatted by VARS."
  (message (apply #'format (concat "cmake-tools [%s]: " str) (cons (current-time-string) vars))))

(defun cmake-tools-utils-get-cmake-configuration ()
  (if (not (file-exists-p (cmake-tools-config-get-cwd)))
      (cmake-tools-make-a-result CMAKE-TOOLS-CANNOT-FIND-CMAKE-CONFIGURATION-FILE
                                 '()
                                 "Cannot find CMakeLists.txt at cwd.")
    (cmake-tools-make-a-result CMAKE-TOOLS-SUCCESS (s-concat (cmake-tools-config-get-cwd) "CMakeLists.txt") "Found it")))

(provide 'cmake-tools)
;;; cmake-tools.el ends here
