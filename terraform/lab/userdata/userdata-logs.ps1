$ErrorActionPreference = 'Stop'
$ErrorMarker = '[BOOTSTRAP ERROR]'
$LegacyErrorMarker = '🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴'
$ProgressMarker = '[BOOTSTRAP_PROGRESS]'
$CompleteMarker = '[BOOTSTRAP_COMPLETE]'
$ContextLines = 10
$StaleAfterSeconds = 300
$LogPaths = @(
    'C:\ProgramData\WindowsEndpointBootstrap.log',
    'C:\ProgramData\SplunkEndpointBootstrap.log'
)
$FailureCount = 0
$CompletedCount = 0
$InProgressCount = 0
$NotStartedCount = 0

Write-Output "User-data log scan started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
foreach ($LogPath in $LogPaths) {
    Write-Output "`n--- $(Split-Path -Leaf $LogPath) ($LogPath) ---"
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
            Write-Output 'Status: NOT STARTED YET (outer bootstrap has recent activity)'
            $InProgressCount++
        } else {
            Write-Output 'Status: NOT STARTED / NO LOG FILE'
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
        Write-Output "Status: FAILED ($(@($ErrorIndexes).Count) error marker(s))"
        foreach ($ErrorIndex in $ErrorIndexes) {
            $FailureCount++
            $StartIndex = [Math]::Max(0, $ErrorIndex - [Math]::Floor($ContextLines / 2))
            $EndIndex = [Math]::Min($Lines.Count - 1, $ErrorIndex + [Math]::Floor($ContextLines / 2))
            for ($Index = $StartIndex; $Index -le $EndIndex; $Index++) {
                if ($Index -eq $ErrorIndex) {
                    Write-Output ">>> $($Index + 1): $($Lines[$Index])"
                } else {
                    Write-Output "    $($Index + 1): $($Lines[$Index])"
                }
            }
            Write-Output ''
        }
    } elseif ($CompleteLines.Count -gt 0) {
        Write-Output 'Status: COMPLETED'
        $CompletedCount++
    } else {
        if ($AgeSeconds -le $StaleAfterSeconds) {
            Write-Output "Status: IN_PROGRESS (recent activity; last log write $AgeSeconds seconds ago)"
        } else {
            Write-Output "Status: NOT COMPLETE; possibly stalled (last log write $AgeSeconds seconds ago)"
        }
        $InProgressCount++
    }

    if ($CompleteLines.Count -gt 0) {
        $LatestProgress = $CompleteLines[-1] -replace '^.*\[BOOTSTRAP_COMPLETE\]\s*', ''
        Write-Output "Progress: $LatestProgress"
    } elseif ($ProgressLines.Count -gt 0) {
        $LatestProgress = $ProgressLines[-1] -replace '^.*\[BOOTSTRAP_PROGRESS\]\s*', ''
        Write-Output "Progress: $LatestProgress"
    } else {
        Write-Output 'Progress: not reported by this log version'
    }
}

Write-Output "`nSummary: completed=$CompletedCount in-progress-or-possibly-stalled=$InProgressCount not-started=$NotStartedCount failed=$FailureCount"
Write-Output "User-data log scan finished: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
if ($FailureCount -gt 0) { exit 1 }
exit 0
