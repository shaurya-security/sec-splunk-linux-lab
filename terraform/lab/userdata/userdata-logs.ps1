$ErrorActionPreference = 'Stop'
$ErrorMarker = '[BOOTSTRAP ERROR]'
$LegacyErrorMarker = '🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴'
$ProgressMarker = '[BOOTSTRAP_PROGRESS]'
$CompleteMarker = '[BOOTSTRAP_COMPLETE]'
$ContextLines = 10
$StaleAfterSeconds = 300
$LogPaths = @(
    'C:\Soc-Lab\logs\WindowsEndpointBootstrap.log',
    'C:\Soc-Lab\logs\SplunkEndpointBootstrap.log'
)
$FailureCount = 0
$CompletedCount = 0
$InProgressCount = 0
$NotStartedCount = 0

function Write-Banner([string]$Title) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkCyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 68) -ForegroundColor DarkCyan
}

function Write-Section([string]$Title) {
    Write-Host "`n--- $Title ---" -ForegroundColor Cyan
}

function Write-Status([string]$Text, [string]$Kind) {
    $Color = switch ($Kind) {
        'COMPLETED' { 'Green' }
        'IN_PROGRESS' { 'Yellow' }
        'NOT_STARTED' { 'DarkYellow' }
        'FAILED' { 'Red' }
        default { 'Gray' }
    }
    Write-Host ('  {0,-14} {1}' -f $Kind, $Text) -ForegroundColor $Color
}

function Write-ProgressBar([string]$Text) {
    if ($Text -match '^(?<Percent>\d{1,3})%\s*-\s*(?<Stage>.*)$') {
        $Percent = [Math]::Min(100, [int]$Matches.Percent)
        $Filled = [Math]::Floor($Percent / 5)
        $Bar = ('#' * $Filled) + ('-' * (20 - $Filled))
        Write-Host ('  Progress        [{0}] {1,3}%  {2}' -f $Bar, $Percent, $Matches.Stage) -ForegroundColor Cyan
    } elseif ($Text) {
        Write-Host "  Progress        $Text" -ForegroundColor Cyan
    } else {
        Write-Host '  Progress        not reported by this log version' -ForegroundColor DarkGray
    }
}

Write-Banner 'WINDOWS USER-DATA STATUS'
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
foreach ($LogPath in $LogPaths) {
    Write-Section $LogPath
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        $OuterLog = $LogPaths[0]
        $OuterStillRunning = $false
        if ((Test-Path -LiteralPath $OuterLog -PathType Leaf) -and ($LogPath -ne $OuterLog)) {
            $OuterLines = Get-Content -LiteralPath $OuterLog
            $OuterItem = Get-Item -LiteralPath $OuterLog
            $OuterAge = [int]((Get-Date) - $OuterItem.LastWriteTime).TotalSeconds
            $OuterHasTerminal = ($OuterLines -match '\[BOOTSTRAP_COMPLETE\]|\[BOOTSTRAP ERROR\]')
            $OuterStillRunning = (-not $OuterHasTerminal -and $OuterAge -le $StaleAfterSeconds)
        }
        if ($OuterStillRunning) {
            Write-Status 'outer bootstrap has recent activity' 'NOT_STARTED'
            $InProgressCount++
        } else {
            Write-Status 'expected log file is missing' 'FAILED'
            $NotStartedCount++
            $FailureCount++
        }
        continue
    }

    $Item = Get-Item -LiteralPath $LogPath
    $Lines = Get-Content -LiteralPath $LogPath
    $AgeSeconds = [int]((Get-Date) - $Item.LastWriteTime).TotalSeconds
    $ErrorIndexes = for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index].Contains($ErrorMarker) -or $Lines[$Index].Contains($LegacyErrorMarker)) {
            $Index
        }
    }
    $ProgressLines = @($Lines | Where-Object { $_.Contains($ProgressMarker) })
    $CompleteLines = @($Lines | Where-Object { $_.Contains($CompleteMarker) })

    if (@($ErrorIndexes).Count -gt 0) {
        Write-Status "$(@($ErrorIndexes).Count) error marker(s) found" 'FAILED'
        foreach ($ErrorIndex in $ErrorIndexes) {
            $FailureCount++
            $StartIndex = [Math]::Max(0, $ErrorIndex - [Math]::Floor($ContextLines / 2))
            $EndIndex = [Math]::Min($Lines.Count - 1, $ErrorIndex + [Math]::Floor($ContextLines / 2))
            for ($Index = $StartIndex; $Index -le $EndIndex; $Index++) {
                $Line = '{0,5}: {1}' -f ($Index + 1), $Lines[$Index]
                if ($Index -eq $ErrorIndex) {
                    Write-Host ">>> $Line" -ForegroundColor Red
                } else {
                    Write-Host "    $Line" -ForegroundColor DarkGray
                }
            }
            Write-Host ''
        }
    } elseif ($CompleteLines.Count -gt 0) {
        Write-Status 'completion marker found' 'COMPLETED'
        $CompletedCount++
    } else {
        if ($AgeSeconds -le $StaleAfterSeconds) {
            Write-Status "recent activity; last write $AgeSeconds seconds ago" 'IN_PROGRESS'
        } else {
            Write-Status "no terminal marker; possibly stalled; last write $AgeSeconds seconds ago" 'IN_PROGRESS'
        }
        $InProgressCount++
    }

    if ($CompleteLines.Count -gt 0) {
        $LatestProgress = $CompleteLines[-1] -replace '^.*\[BOOTSTRAP_COMPLETE\]\s*', ''
    } elseif ($ProgressLines.Count -gt 0) {
        $LatestProgress = $ProgressLines[-1] -replace '^.*\[BOOTSTRAP_PROGRESS\]\s*', ''
    } else {
        $LatestProgress = ''
    }
    Write-ProgressBar $LatestProgress
}

Write-Host ''
Write-Host ('=' * 68) -ForegroundColor DarkCyan
if ($FailureCount -gt 0) {
    Write-Status "completed=$CompletedCount in-progress=$InProgressCount missing=$NotStartedCount failed=$FailureCount" 'FAILED'
} elseif ($InProgressCount -gt 0) {
    Write-Status "completed=$CompletedCount in-progress=$InProgressCount" 'IN_PROGRESS'
} else {
    Write-Status "all expected logs completed=$CompletedCount" 'COMPLETED'
}
Write-Host "Finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ('=' * 68) -ForegroundColor DarkCyan
if ($FailureCount -gt 0) { exit 1 }
exit 0
