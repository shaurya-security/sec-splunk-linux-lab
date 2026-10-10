param(
    [Parameter(Mandatory = $true)][string]$SplunkPrivateIp,
    [Parameter(Mandatory = $true)][string]$UfS3Uri,
    [Parameter(Mandatory = $true)][string]$UfPackageKey
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SocLabDir = 'C:\Soc-Lab'
$SocLabConfigDir = Join-Path $SocLabDir 'config'
$SocLabLogDir = Join-Path $SocLabDir 'logs'
$SocLabPackageDir = Join-Path $SocLabDir 'packages'
New-Item -Path $SocLabConfigDir, $SocLabLogDir, $SocLabPackageDir -ItemType Directory -Force | Out-Null
$LogPath = Join-Path $SocLabLogDir 'SplunkEndpointBootstrap.log'
Start-Transcript -Path $LogPath -Append

try {
    Write-Output '[BOOTSTRAP_PROGRESS] 0% - Windows forwarder setup started'
    $InstallerPath = Join-Path $SocLabPackageDir $UfPackageKey
    $RequestedInstallPath = 'C:\Program Files\SplunkUniversalForwarder'

    $ReceiverReady = $false
    for ($Attempt = 1; $Attempt -le 60; $Attempt++) {
        try {
            $Tcp = New-Object System.Net.Sockets.TcpClient
            $Async = $Tcp.BeginConnect($SplunkPrivateIp, 9997, $null, $null)
            if ($Async.AsyncWaitHandle.WaitOne(5000, $false) -and $Tcp.Connected) {
                $Tcp.EndConnect($Async)
                $ReceiverReady = $true
                $Tcp.Close()
                break
            }
            $Tcp.Close()
        } catch { }
        Start-Sleep -Seconds 10
    }
    if (-not $ReceiverReady) { throw 'Splunk receiver TCP/9997 did not become reachable.' }
    Write-Output '[BOOTSTRAP_PROGRESS] 20% - Splunk receiver is reachable'
    if ([string]::IsNullOrWhiteSpace($UfPackageKey) -or [IO.Path]::GetExtension($UfPackageKey) -ne '.msi') {
        throw 'windows_uf_package_key must be the S3 object name of the Universal Forwarder MSI.'
    }

    $MetadataToken = Invoke-RestMethod -Method Put -Uri 'http://169.254.169.254/latest/api/token' -Headers @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '300' }
    $Region = Invoke-RestMethod -Headers @{ 'X-aws-ec2-metadata-token' = $MetadataToken } -Uri 'http://169.254.169.254/latest/meta-data/placement/region'
    $AwsExe = (Get-Command aws.exe -ErrorAction SilentlyContinue).Source
    if (-not $AwsExe) { $AwsExe = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe' }
    if (-not (Test-Path $AwsExe -PathType Leaf)) { throw 'AWS CLI v2 is required to retrieve the Universal Forwarder MSI from S3.' }
    $Downloaded = $false
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        & $AwsExe s3 cp $UfS3Uri $InstallerPath --region $Region
        if ($LASTEXITCODE -eq 0 -and (Test-Path $InstallerPath -PathType Leaf)) {
            $Downloaded = $true
            break
        }
        Start-Sleep -Seconds 5
    }
    if (-not $Downloaded) { throw 'Could not download the Windows Universal Forwarder MSI.' }
    Write-Output '[BOOTSTRAP_PROGRESS] 40% - Universal Forwarder package downloaded into C:\Soc-Lab\packages'

    $Install = Start-Process msiexec.exe -ArgumentList @('/i', $InstallerPath, '/qn', 'AGREETOLICENSE=Yes', "INSTALLDIR=`"$RequestedInstallPath`"") -Wait -PassThru
    if ($Install.ExitCode -ne 0) { throw "Universal Forwarder MSI failed with exit code $($Install.ExitCode)." }

    $UninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $ForwarderEntries = @(foreach ($Key in $UninstallKeys) {
        Get-ItemProperty -Path $Key -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -match '(?i)(splunk.*forwarder|universal.*forwarder)' }
    })
    $InstallCandidates = @(
        $ForwarderEntries | ForEach-Object { $_.InstallLocation }
        $RequestedInstallPath
        (Join-Path $env:ProgramFiles 'SplunkUniversalForwarder')
        (Join-Path ${env:ProgramFiles(x86)} 'SplunkUniversalForwarder')
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $SplunkExe = $null
    foreach ($Candidate in $InstallCandidates) {
        $CandidateExe = Join-Path $Candidate 'bin\splunk.exe'
        if (Test-Path -LiteralPath $CandidateExe -PathType Leaf) {
            $SplunkExe = $CandidateExe
            break
        }
    }
    if (-not $SplunkExe) {
        $RegistryLocations = ($ForwarderEntries | ForEach-Object { $_.InstallLocation } | Where-Object { $_ }) -join ', '
        throw "MSI exited successfully but splunk.exe was not found. Requested path: $RequestedInstallPath; registry install locations: $RegistryLocations"
    }

    $InstallPath = Split-Path -Parent (Split-Path -Parent $SplunkExe)
    $AppLocal = Join-Path $InstallPath 'etc\apps\lab_endpoint\local'
    Write-Output "[BOOTSTRAP_PROGRESS] 60% - Universal Forwarder located at $InstallPath"

    $OutputsConfig = Join-Path $SocLabConfigDir 'outputs.conf'
    $InputsConfig = Join-Path $SocLabConfigDir 'inputs.conf'
    @"
[tcpout]
defaultGroup = splunk_receiver

[tcpout:splunk_receiver]
server = $($SplunkPrivateIp):9997
useACK = true
"@ | Set-Content -Path $OutputsConfig -Encoding ASCII

    @'
[WinEventLog://Application]
disabled = 0
index = windows_endpoint
renderXml = true

[WinEventLog://System]
disabled = 0
index = windows_endpoint
renderXml = true

[WinEventLog://Security]
disabled = 0
index = windows_endpoint
renderXml = true
'@ | Set-Content -Path $InputsConfig -Encoding ASCII

    New-Item -Path $AppLocal -ItemType Directory -Force | Out-Null
    Copy-Item -Path $OutputsConfig -Destination (Join-Path $AppLocal 'outputs.conf') -Force
    Copy-Item -Path $InputsConfig -Destination (Join-Path $AppLocal 'inputs.conf') -Force
    Write-Output "[BOOTSTRAP_PROGRESS] 80% - authored forwarder configs stored in $SocLabConfigDir and installed in $AppLocal"

    & $SplunkExe start --accept-license --answer-yes --no-prompt
    & $SplunkExe enable boot-start
    Set-Service -Name SplunkForwarder -StartupType Automatic
    Start-Service -Name SplunkForwarder
    Write-Output '[BOOTSTRAP_COMPLETE] 100% - Windows Universal Forwarder configured'
} catch {
    Write-Error "[BOOTSTRAP ERROR] $_"
    exit 1
} finally {
    Stop-Transcript
}
