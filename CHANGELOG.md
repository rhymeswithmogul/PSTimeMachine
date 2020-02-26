# PSTimeMachine Change Log

## Version 1.0.3 (2020-02-21)
 - If a file is in use and can't be copied, PSTimeMachine will now keep running instead of terminating.
 - If a copy-only backup is performed, file names will now be written to the log file.
 - Resolve-Path has replaced -Replace for calculating relative paths.
 - Changed Join-Path behavior for compatibility with Windows PowerShell 5.1.
 - Miscellaneous code cleanup.
 - Better error handling.

## Version 1.0.2 (2019-06-03)
 - Fixed a bug where an initial or -NoHardLinks backup would not show verbose errors when -Verbose was supplied.
 - Fixed a bug where the script would terminate before completion if transcription were not enabled.
 - More example documentation.

## Version 1.0.1 (2019-04-15)
 - Changed the log file name from global to script scope.
 - The source path is now validated to make sure it is a valid path and that it exists.
 - This script requires PowerShell 5 or newer, for hard link support, but it was possible to run this script on older versions.  The check is now enforced.
 - Miscellaneous code cleanup.

## Version 1.0 (2019-04-09)
Initial release.