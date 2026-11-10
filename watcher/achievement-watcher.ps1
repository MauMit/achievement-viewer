# ============================================================
# Achievement Viewer - Automatic GSE + Goldberg Watcher
# ============================================================
#
# Watches:
#   %APPDATA%\GSE Saves
#   %APPDATA%\Goldberg SteamEmu Saves
#
# When achievements.json changes:
#   1. Waits for the emulator to finish writing
#   2. Validates the JSON
#   3. Copies it to AppID\<AppID>\achievements.json
#   4. Commits the change
#   5. Pushes it to the GitHub "user" branch
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File achievement-watcher.ps1
#   powershell -ExecutionPolicy Bypass -File achievement-watcher.ps1 -RepoPath "D:\path\to\achievement-viewer"
#
# -RepoPath must be a local clone of this repo checked out on the "user" branch.
# ============================================================

param(
    [string]$RepoPath = (Join-Path $env:USERPROFILE "Desktop\Egna Projekt\achievement-viewer\achievement-viewer")
)


# ------------------------------------------------------------
# CONFIGURATION
# ------------------------------------------------------------

$GSEPath = Join-Path $env:APPDATA "GSE Saves"

$GoldbergPath = Join-Path $env:APPDATA "Goldberg SteamEmu Saves"

$AppIDPath = Join-Path $RepoPath "AppID"

# Wait this many seconds after an emulator changes achievements.json.
$WriteDelaySeconds = 5

# Wait this many seconds before committing.
# This helps combine several quick achievement updates into one commit.
$CommitDelaySeconds = 5


# ------------------------------------------------------------
# GLOBAL STATE
# ------------------------------------------------------------

$script:GitSyncRunning = $false


# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------

function Write-Log {

    param(
        [string]$Message
    )

    $Time = Get-Date -Format "HH:mm:ss"

    Write-Host "[$Time] $Message"
}


# ------------------------------------------------------------
# CHECK APPID
# ------------------------------------------------------------

function Test-SteamAppID {

    param(
        [string]$AppID
    )

    if ($AppID -match '^\d+$') {
        return $true
    }

    return $false
}


# ------------------------------------------------------------
# CHECK JSON
# ------------------------------------------------------------

function Test-AchievementJSON {

    param(
        [string]$File
    )

    if (-not (Test-Path -LiteralPath $File)) {
        return $false
    }

    try {

        $Content = Get-Content -LiteralPath $File -Raw -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $false
        }

        $null = $Content | ConvertFrom-Json -ErrorAction Stop

        return $true

    }
    catch {

        return $false
    }
}


# ------------------------------------------------------------
# GIT SYNC
# ------------------------------------------------------------

function Start-GitSync {

    if ($script:GitSyncRunning) {

        Write-Log "Git sync is already running. Skipping duplicate request."

        return
    }

    $script:GitSyncRunning = $true

    try {

        Write-Log "Waiting $CommitDelaySeconds seconds before Git sync..."

        Start-Sleep -Seconds $CommitDelaySeconds

        Set-Location -LiteralPath $RepoPath

        # ----------------------------------------------------
        # Verify Git repository
        # ----------------------------------------------------

        git rev-parse --is-inside-work-tree *> $null

        if ($LASTEXITCODE -ne 0) {
            throw "The configured repository folder is not a Git repository."
        }


        # ----------------------------------------------------
        # Check current branch
        # ----------------------------------------------------

        $CurrentBranch = (git branch --show-current).Trim()

        Write-Log "Current Git branch: $CurrentBranch"


        # ----------------------------------------------------
        # Switch to user branch if necessary
        # ----------------------------------------------------

        if ($CurrentBranch -ne "user") {

            Write-Log "Switching to user branch..."

            git checkout user

            if ($LASTEXITCODE -ne 0) {
                throw "Could not switch to the user branch."
            }
        }


        # ----------------------------------------------------
        # Stage AppID changes
        # ----------------------------------------------------

        Write-Log "Checking for achievement changes..."

        git add -A AppID

        if ($LASTEXITCODE -ne 0) {
            throw "git add failed."
        }


        # ----------------------------------------------------
        # Check staged changes
        # ----------------------------------------------------

        git diff --cached --quiet

        $HasStagedChanges = ($LASTEXITCODE -ne 0)

        # Commits left over from an earlier failed push still need uploading
        $Unpushed = [int](git rev-list --count "origin/user..user" 2>$null)

        if (-not $HasStagedChanges -and $Unpushed -eq 0) {

            Write-Log "No achievement changes need to be uploaded."

            return
        }


        if ($HasStagedChanges) {

            # ------------------------------------------------
            # Display changes
            # ------------------------------------------------

            Write-Log "Changes detected:"

            git status --short


            # ------------------------------------------------
            # Commit
            # ------------------------------------------------

            $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

            Write-Log "Creating Git commit..."

            git commit -m "Sync achievements - $Timestamp"

            if ($LASTEXITCODE -ne 0) {
                throw "Git commit failed."
            }
        }
        else {

            Write-Log "Uploading $Unpushed earlier commit(s) that weren't pushed yet..."
        }


        # ----------------------------------------------------
        # Pull first
        # ----------------------------------------------------
        # After each push, GitHub Actions commits updated game data
        # ("Update game data [skip ci]") to the user branch. Pull it in
        # before pushing, or the next push is rejected as out of date.
        # The bot only touches game-info.json / game-data.json and this
        # script only touches achievements.json, so a rebase is safe.

        Write-Log "Pulling latest user branch from GitHub..."

        git pull --rebase --autostash origin user

        if ($LASTEXITCODE -ne 0) {
            git rebase --abort *> $null
            throw "git pull failed. Your commit is kept locally; it will be pushed with the next change."
        }


        # ----------------------------------------------------
        # Push
        # ----------------------------------------------------

        Write-Log "Pushing to GitHub user branch..."

        git push origin user

        if ($LASTEXITCODE -ne 0) {
            throw "Git push failed."
        }


        Write-Host ""
        Write-Log "SUCCESS!"
        Write-Log "Achievement changes were uploaded to GitHub."
        Write-Host ""

    }
    catch {

        Write-Host ""
        Write-Log "ERROR: $($_.Exception.Message)"
        Write-Host ""

    }
    finally {

        $script:GitSyncRunning = $false
    }
}


# ------------------------------------------------------------
# COPY ACHIEVEMENT FILE
# ------------------------------------------------------------

function Sync-AchievementFile {

    param(
        [string]$SourceFile,
        [string]$SourceName
    )

    Write-Host ""

    Write-Log "${SourceName}: achievement file changed."

    Write-Log "File:"
    Write-Log "  $SourceFile"


    # --------------------------------------------------------
    # Wait for emulator to finish writing
    # --------------------------------------------------------

    Write-Log "Waiting $WriteDelaySeconds seconds for emulator to finish writing..."

    Start-Sleep -Seconds $WriteDelaySeconds


    # --------------------------------------------------------
    # Make sure file still exists
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $SourceFile)) {

        Write-Log "File no longer exists. Ignoring."

        return
    }


    # --------------------------------------------------------
    # Determine AppID
    # --------------------------------------------------------

    $ParentFolder = Split-Path -Path $SourceFile -Parent

    $AppID = Split-Path -Path $ParentFolder -Leaf


    if (-not (Test-SteamAppID -AppID $AppID)) {

        Write-Log "Ignoring folder because '$AppID' is not a Steam AppID."

        return
    }


    Write-Log "Detected Steam AppID: $AppID"


    # --------------------------------------------------------
    # Validate JSON
    # --------------------------------------------------------

    if (-not (Test-AchievementJSON -File $SourceFile)) {

        Write-Log "JSON isn't ready yet."

        Write-Log "Waiting another 5 seconds..."

        Start-Sleep -Seconds 5


        if (-not (Test-AchievementJSON -File $SourceFile)) {

            Write-Log "ERROR: achievements.json is not valid JSON."

            return
        }
    }


    Write-Log "Achievement JSON is valid."


    # --------------------------------------------------------
    # Destination
    # --------------------------------------------------------

    $DestinationFolder = Join-Path $AppIDPath $AppID

    $DestinationFile = Join-Path $DestinationFolder "achievements.json"


    # --------------------------------------------------------
    # Create AppID folder
    # --------------------------------------------------------

    if (-not (Test-Path -LiteralPath $DestinationFolder)) {

        New-Item `
            -ItemType Directory `
            -Path $DestinationFolder `
            -Force | Out-Null

        Write-Log "Created AppID\$AppID"
    }


    # --------------------------------------------------------
    # Check whether source and destination are identical
    # --------------------------------------------------------

    $NeedsCopy = $true

    if (Test-Path -LiteralPath $DestinationFile) {

        try {

            $SourceHash = (
                Get-FileHash `
                    -LiteralPath $SourceFile `
                    -Algorithm SHA256
            ).Hash

            $DestinationHash = (
                Get-FileHash `
                    -LiteralPath $DestinationFile `
                    -Algorithm SHA256
            ).Hash


            if ($SourceHash -eq $DestinationHash) {

                $NeedsCopy = $false
            }

        }
        catch {

            # If hash comparison fails, just copy the file.
            $NeedsCopy = $true
        }
    }


    # --------------------------------------------------------
    # Copy
    # --------------------------------------------------------

    if (-not $NeedsCopy) {

        Write-Log "Repository already contains this exact achievement file."

        return
    }


    Copy-Item `
        -LiteralPath $SourceFile `
        -Destination $DestinationFile `
        -Force


    Write-Log "Copied achievement data:"

    Write-Log "  $SourceName"

    Write-Log "  AppID $AppID"

    Write-Log "  -> AppID\$AppID\achievements.json"


    # --------------------------------------------------------
    # Git
    # --------------------------------------------------------

    Start-GitSync
}


# ------------------------------------------------------------
# CREATE FILE WATCHER
# ------------------------------------------------------------

function New-AchievementWatcher {

    param(
        [string]$Path,
        [string]$Name
    )


    if (-not (Test-Path -LiteralPath $Path)) {

        Write-Log "${Name}: folder not found."

        Write-Log "  $Path"

        return $null
    }


    $Watcher = New-Object System.IO.FileSystemWatcher

    $Watcher.Path = $Path

    $Watcher.Filter = "achievements.json"

    $Watcher.IncludeSubdirectories = $true

    $Watcher.NotifyFilter = (
        [System.IO.NotifyFilters]::FileName `
        -bor
        [System.IO.NotifyFilters]::LastWrite `
        -bor
        [System.IO.NotifyFilters]::Size
    )

    $Watcher.EnableRaisingEvents = $true


    # --------------------------------------------------------
    # Changed event
    # --------------------------------------------------------

    $ChangedAction = {

        $ChangedFile = $Event.SourceEventArgs.FullPath

        $EmulatorName = $Event.MessageData


        Sync-AchievementFile `
            -SourceFile $ChangedFile `
            -SourceName $EmulatorName
    }


    Register-ObjectEvent `
        -InputObject $Watcher `
        -EventName Changed `
        -MessageData $Name `
        -Action $ChangedAction | Out-Null


    # --------------------------------------------------------
    # Created event
    # --------------------------------------------------------

    $CreatedAction = {

        $CreatedFile = $Event.SourceEventArgs.FullPath

        $EmulatorName = $Event.MessageData


        Sync-AchievementFile `
            -SourceFile $CreatedFile `
            -SourceName $EmulatorName
    }


    Register-ObjectEvent `
        -InputObject $Watcher `
        -EventName Created `
        -MessageData $Name `
        -Action $CreatedAction | Out-Null


    Write-Log "Watching ${Name}:"

    Write-Log "  $Path"


    return $Watcher
}


# ============================================================
# START
# ============================================================

Clear-Host


Write-Host ""
Write-Host "============================================================"
Write-Host " Achievement Viewer"
Write-Host " Automatic GSE + Goldberg Achievement Sync"
Write-Host "============================================================"
Write-Host ""


# ------------------------------------------------------------
# Verify repository
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $RepoPath)) {

    Write-Host "ERROR:"
    Write-Host ""
    Write-Host "Repository folder does not exist:"
    Write-Host ""
    Write-Host $RepoPath
    Write-Host ""

    Read-Host "Press Enter to exit"

    exit 1
}


if (-not (Test-Path -LiteralPath $AppIDPath)) {

    New-Item `
        -ItemType Directory `
        -Path $AppIDPath `
        -Force | Out-Null
}


Set-Location -LiteralPath $RepoPath


Write-Log "Repository:"

Write-Log "  $RepoPath"

Write-Host ""


# ------------------------------------------------------------
# Start watchers
# ------------------------------------------------------------

$Watchers = @()


$GSEWatcher = New-AchievementWatcher `
    -Path $GSEPath `
    -Name "GSE"


if ($null -ne $GSEWatcher) {

    $Watchers += $GSEWatcher
}


$GoldbergWatcher = New-AchievementWatcher `
    -Path $GoldbergPath `
    -Name "Goldberg"


if ($null -ne $GoldbergWatcher) {

    $Watchers += $GoldbergWatcher
}


# ------------------------------------------------------------
# Make sure at least one folder exists
# ------------------------------------------------------------

if ($Watchers.Count -eq 0) {

    Write-Host ""
    Write-Host "ERROR:"
    Write-Host ""
    Write-Host "Neither achievement save folder could be found."
    Write-Host ""

    Read-Host "Press Enter to exit"

    exit 1
}


# ------------------------------------------------------------
# Running
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================"
Write-Host " Watcher is running"
Write-Host "============================================================"
Write-Host ""

Write-Host "Watching for:"
Write-Host ""

Write-Host " GSE:"
Write-Host " $GSEPath"
Write-Host ""

Write-Host " Goldberg:"
Write-Host " $GoldbergPath"
Write-Host ""

Write-Host "When achievements.json changes:"
Write-Host ""
Write-Host "  Game / emulator"
Write-Host "       |"
Write-Host "       v"
Write-Host "  achievements.json"
Write-Host "       |"
Write-Host "       v"
Write-Host "  AppID folder"
Write-Host "       |"
Write-Host "       v"
Write-Host "  Git commit + push"
Write-Host "       |"
Write-Host "       v"
Write-Host "  GitHub Action"
Write-Host "       |"
Write-Host "       v"
Write-Host "  Achievement Viewer"
Write-Host ""

Write-Host "Waiting for achievement changes..."
Write-Host ""
Write-Host "Press CTRL+C to stop."
Write-Host ""


# ------------------------------------------------------------
# Keep PowerShell alive
# ------------------------------------------------------------

try {

    while ($true) {

        Wait-Event -Timeout 5 | Out-Null
    }

}
finally {

    Write-Host ""
    Write-Log "Stopping achievement watcher..."

    Get-EventSubscriber | Unregister-Event -Force

    foreach ($Watcher in $Watchers) {

        $Watcher.EnableRaisingEvents = $false

        $Watcher.Dispose()
    }
}