$ErrorActionPreference = 'Stop'
$ErrorMarker = '[BOOTSTRAP ERROR]'
$LegacyErrorMarker = '🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴'
$ContextLines = 10
$LogPaths = @(
    'C:\ProgramData\WindowsEndpointBootstrap.log',
    'C:\ProgramData\SplunkEndpointBootstrap.log'
)
$FailureCount = 0

Write-Output "Bootstrap log scan started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
foreach ($LogPath in $LogPaths) {
    Write-Output "`n--- $(Split-Path -Leaf $LogPath) ($LogPath) ---"
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        Write-Output 'Not present on this instance; skipping.'
        continue
    }

    $Lines = Get-Content -LiteralPath $LogPath
    $ErrorIndexes = for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index].Contains($ErrorMarker) -or $Lines[$Index].Contains($LegacyErrorMarker)) {
            $Index
        }
    }
    if (@($ErrorIndexes).Count -eq 0) {
        Write-Output 'No bootstrap error markers found.'
        continue
    }

    Write-Output "Found $($ErrorIndexes.Count) error marker(s)."
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
}

Write-Output "Bootstrap log scan completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); error markers found: $FailureCount"
if ($FailureCount -gt 0) { exit 1 }
exit 0
