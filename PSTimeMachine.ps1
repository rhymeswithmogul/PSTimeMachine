<#
.NOTES
PSTimeMachine.ps1 - Version 1.0.3
(c) 2019-2020 Colin Cogle <colin@colincogle.name>

This program is free software:  you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program. If not, see <https://www.gnu.org/licenses/>.

.LINK
https://github.com/rhymeswithmogul/PSTimeMachine

.SYNOPSIS
Creates versioned, deduplicated backups of a folder.

.DESCRIPTION
This script creates backups in the style of Apple's Time Machine by copying
files to a destination, placing them into deduplicated subfolders based on the
backup time.

.NOTES
The backup destination's filesystem must support hard links for deduplication
to occur.  Hard links are supported on NTFS, HFS+, APFS, and all UNIX and
Linux filesystems.  They are not supported on FAT, exFAT, or ReFS volumes;
and may or may not be supported on SMB shares.

.INPUTS
Instead of specifying SourcePath as a parameter, it may also be specified via
the pipeline.

.OUTPUTS
None.

.PARAMETER SourcePath
The file or folder to back up, recursively. This may also be specified via the
pipeline.

.PARAMETER DestinationPath
The folder in which to place the backed-up files.  If the destination folder
does not exist, this script will attempt to create it.

.PARAMETER FailIfOldBackupsAreMissing
If the destination folder does not exist, or if previous backups cannot be
found inside it, terminate the backup immediately.  This can be used to
strictly check if a destination disk is available before trying to copy files
to it.

.PARAMETER NoHardLinks
All files will be copied, rather than hard-linked, even if they have not
changed since the last backup.  Note that this will massively increase space
usage on the destination disk.  However, it may be useful or required for
destinations that do not support hard links (like FAT16/FAT32, exFAT, ReFS,
or network volumes).

.PARAMETER NoLogging
Do not create a log file inside the backup folder.  By default, all output is
redirected to that log file.

.PARAMETER NoStatistics
Suppress statistics after a successful backup. Statistics are not reported for
copy-only backups.

.EXAMPLE
PS C:\> .\PSTimeMachine.ps1 -SourcePath C:\Users\jdoe -DestinationPath "D:\Backups"

This backs up C:\Users\jdoe to D:\Backups.

.EXAMPLE
PS C:\Users\jdoe> Get-Location | .\PSTimeMachine.ps1 -DestinationPath "D:\Backups"

This also backs up C:\Users\jdoe to D:\Backups.

.EXAMPLE
PS C:\> Get-Item "C:\Users\jdoe" | .\PSTimeMachine.ps1 -DestinationPath "D:\Backups"

This also backs up C:\Users\jdoe to D:\Backups.

.EXAMPLE
PS C:\Users> Get-ChildItem "jdoe" | .\PSTimeMachine.ps1 -DestinationPath "D:\Backups"

This also backs up C:\Users\jdoe to D:\Backups.
#>

#Requires -Version 5.0  #for the Information stream

[CmdletBinding()]
Param(
	[Parameter(Mandatory, Position=0, ValueFromPipeline=$true)]
	[Alias("Name", "Source", "Path")]
	[ValidateNotNullOrEmpty()]
	[ValidateScript({Test-Path -Path $_})]
	[String]$SourcePath,

	[Parameter(Mandatory, Position=1)]
	[Alias("Destination", "Target")]
	[ValidateNotNullOrEmpty()]
	[String]$DestinationPath,

	[Switch]$FailIfOldBackupsAreMissing = $false,

	[Alias("CopyOnlyBackup")]
	[Switch]$NoHardLinks = $false,

	[Switch]$NoLogging = $false,

	[Switch]$NoStatistics = $false
)

# Change into the source folder.
Push-Location -Path $SourcePath

# We're going to create a folder to hold the backup, named for the current
# date and time.  Format everything except the year with leading zeroes.
New-Variable -Option Constant -Name Today      -Value (Get-Date)
New-Variable -Option Constant -Name FolderName -Value (("{0:yyyy}-{0:MM}-{0:dd}T{0:hh}-{0:mm}-{0:ss}" -f $Today) + ".inProgress")

# Start logging?
$DoVerboseCopy = $VerbosePreference -eq "Continue"
If (-Not $NoLogging) {
    # Set all of our display preference variables to Continue,
    # so that output is captured into the transcript.
    $ErrorActionPreference = "Stop"
    $WarningPreference     = "Continue"
    $InformationPreference = "Continue"
    If ($VerbosePreference -ne "SilentlyContinue") {
        $VerbosePreference = "Continue"
    }
    If ($DebugPreference -ne "SilentlyContinue") {
        $DebugPreference = "Continue"
    }

	${script:LogFile} = (New-TemporaryFile)
	Start-Transcript -Path (${script:LogFile}.Name)
}

# Header
Write-Output -InputObject "Starting backup job at $Today."
Write-Information -MessageData "  Current Folder = $(Get-Location)"
Write-Information -MessageData "  Source         = $SourcePath"
Write-Information -MessageData "  Destination    = $(Join-Path -Path $DestinationPath ($FolderName -CReplace '\.inProgress'))"
Write-Information -MessageData "  Other Options  = $(If ($FailIfOldBackupsAreMissing){'NoFailIfOldBackupsAreMissing'}) $(If ($NoHardLinks){'NoHardLinks'}) $(If ($NoLogging){'NoLogging'}) $(If($NoStatistics){'NoStatistics'})`n"

# Check to see if previous backups exist, if we are asked.
:SanityCheck While ($FailIfOldBackupsAreMissing) {
	Get-ChildItem -Path $DestinationPath | ForEach-Object {
		Write-Debug "Checking to see if $($_.Name) is a backup folder..."
		If ($_.Attributes -CMatch "Directory" ) {
			Break SanityCheck
		}
	}
}

# Create the backup destination.
New-Item -Type Directory -Path (Join-Path -Path $DestinationPath $FolderName) -Force | Out-Null

# Keep some statistics.
$bytesCopied = 0
$bytesTotal  = 0

Try {
	# Has the user explicitly asked for no hard links to be made, by using
	# the -NoHardLinks switch?  If so, do a copy-only backup.
	If ($NoHardLinks) {
        $DoCopyOnlyBackup = $true
    } Else {
        # Determine if we need to do a copy-only backup.
        # Start by looking for old backups in the same destination.
        $PreviousBackups = (Get-ChildItem -Attributes Directory -Path $DestinationPath -Exclude "*.inProgress" -ErrorAction SilentlyContinue `
                                | Where-Object {$_.Name -CMatch "\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}(\.inProgress)?"} `
                                | Sort-Object -Descending CreationTime
                            )
        If ($PreviousBackups.Count -gt 0) {
            Write-Verbose "Previous backup found.  Doing an incremental backup."
            $DoCopyOnlyBackup = $false
            $PreviousBackup = $PreviousBackups[0].Name
        }
        Else {
            If ($FailIfOldBackupsAreMissing) {
                Throw [System.Management.Automation.ItemNotFoundException] "No previous backups were found. Exiting at user request."
            }
            Write-Verbose "Previous backups not found.  Doing a copy-only backup."
            $DoCopyOnlyBackup = $true
        }
    }

    $FilesToBackUp = Get-ChildItem -Path "$SourcePath\" -Force -Recurse -ErrorAction Continue
    Write-Information -MessageData "Found $($FilesToBackUp.Count) files to consider.`n"

    $FilesToBackUp | Where-Object {$_.FullName -ne $LogFile.FullName} | ForEach-Object {
        Write-Debug "Analyzing $_"
        
        Try {
			# These will be the relative source and destination file/folder
			# names.  Windows PowerShell 5.1's Join-Path doesn't support the
			# -AdditionalChildPath, so for compatibility with that old but very
			# common version, we need to wrap Join-Path inside itself.
            $RelativeSourceItemPath      = $_.FullName | Resolve-Path -Relative
            $RelativeDestinationItemPath = (Join-Path -Path (Join-Path -Path $DestinationPath -ChildPath $FolderName) -ChildPath $RelativeSourceItemPath)
    
	    	# Create directories, but compare files.
	    	If ($_.Attributes -CMatch "Directory") {
		    	Write-Debug -Message "Create folder: $RelativeDestinationItemPath"
		    	New-Item -Type Directory -Path $RelativeDestinationItemPath | Out-Null
		    }
	    	Else {
			    # Compare file sizes and dates to determine if something has changed.
			    If (-Not $DoCopyOnlyBackup) {
				    $PreviousCopyOfFile = Get-Item -Path (Join-Path -Path (Join-Path -Path $DestinationPath -ChildPath $PreviousBackup) -ChildPath $RelativeSourceItemPath)
				    If (($_.LastWriteTime -eq $PreviousCopyOfFile.LastWriteTime) -And ($_.Length -eq $PreviousCopyOfFile.Length)) {
					    # The file has not changed since the last backup.  Create a hard link.
					    $DestinationHardlink = @{
						    ItemType    = "HardLink"
						    Target      = ($PreviousCopyOfFile.FullName)
						    Path        = ($PreviousCopyOfFile | Split-Path -Parent) -Replace [regex]::Escape($PreviousBackup),$FolderName
						    Name        = ($PreviousCopyOfFile.Name)
					    }
					    Write-Verbose "Linking unchanged file: $RelativeSourceItemPath"
					    New-Item @DestinationHardlink | Out-Null
				    }
				    Else {
					    Write-Verbose "Copying changed file: $RelativeSourceItemPath"
					    Copy-Item -Path $_.FullName -Destination $RelativeDestinationItemPath -Verbose:$DoVerboseCopy
					    $bytesCopied += $_.Length
				    }
			    } Else {
				    Write-Verbose "Copying: $RelativeSourceItemPath"
				    Copy-Item -Path $_.FullName -Destination $RelativeDestinationItemPath -Verbose:$DoVerboseCopy
				    $bytesCopied += $_.Length
			    }
			    $bytesTotal  += $_.Length
            }
		}
        Catch {
            Write-Warning "Failed to back up: $RelativeSourceItemPath"
        }
	}

	Write-Information -MessageData "Backup completed at $(Get-Date)."
	Rename-Item -Path (Join-Path -Path $DestinationPath -ChildPath $FolderName) -NewName ($FolderName -CReplace '\.inProgress')
	If (-Not $NoStatistics -And $bytesTotal -gt 0) {
		$pctCopied = $bytesCopied / $bytesTotal
		Write-Information -MessageData "Copied $($bytesCopied / 1048576) MB out of $($bytesTotal / 1048576) MB: $('{0:p0}' -f (1 - $pctCopied)) percent savings."
	}
}
Catch {
	Write-Error "Backup failed at $(Get-Date); removing in-progress backup!`nError: $($_.Exception.Message)"
	Remove-Item -Recurse -Force (Join-Path -Path $DestinationPath -ChildPath $FolderName)
}
Finally {
	If (-Not $NoLogging) {
		Write-Verbose "Moving log file to backup destination."
		Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
		Write-Debug "Moving $(${script:LogFile}.FullName) to $(Join-Path -Path $DestinationPath -ChildPath 'PSTimeMachine.log')"
        Rename-Item -Path ${script:LogFile}.FullName -NewName "PSTimeMachine-$FolderName.log" -PassThru `
            | Move-Item -Destination (Join-Path -Path (Join-Path -Path $DestinationPath -ChildPath $FolderName) -ChildPath "PSTimeMachine.log") -ErrorAction SilentlyContinue
	}

	# Restore the user's environment.
	Pop-Location
}
