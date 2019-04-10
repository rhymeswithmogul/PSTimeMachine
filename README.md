# PSTimeMachine
One day, I was so mad at a backup vendor *and* at Windows Server Backup, that I wrote my own simple backup tool in PowerShell.

Apple's Time Machine and <a href="https://git.samba.org/?p=rsync.git"><tt>rsync</tt></a> were the inspirations for this:
* **Versioned:** Every time the tool runs, a new folder tree is created.
* **Secure:**    Old backups are never added to nor modified by this tool.
* **Simple:**    It creates entire, browseable folder trees at the destination that require no tools to restore from.
* **Efficient:** Only changed files are copied from the source to the destination; unchanged files are added with filesystem-level hard links.

## Requirements
1. The system must be running PowerShell Core or at least Windows PowerShell 5.
2. Ideally, your backup destination should support hard links.  If not, backups will use a *lot* of space.

## How to Use It
Like this:

    .\PSTimeMachine.ps1 -SourcePath C:\Shares\SomeShare -DestinationPath D:\BackupsOfSomeShare

For help:

    Get-Help .\PSTimeMachine.ps1
    
## Contributing
Please do!
