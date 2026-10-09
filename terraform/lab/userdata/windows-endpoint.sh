param(
    [Parameter(Mandatory = $true)][string]$SplunkPrivateIp,
    [Parameter(Mandatory = $true)][string]$UfS3Uri,
    [Parameter(Mandatory = $true)][string]$UfPackageKey
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$LogPath = 'C:\ProgramData\SplunkEndpointBootstrap.log'
Start-Transcript -Path $LogPath -Append

try {
    Write-Output '[BOOTSTRAP_PROGRESS] 0% - Windows forwarder setup started'
    $InstallerPath = Join-Path $env:TEMP $UfPackageKey
    $InstallPath = 'C:\Program Files\SplunkUniversalForwarder'
    $AppLocal = Join-Path $InstallPath 'etc\apps\lab_endpoint\local'

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
    if (-not $AwsExe) { $AwsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe' }
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
    if (-not $Downloaded) { throw 'Could not download the Windows Universal Forwarder MSI from S3.' }
    Write-Output '[BOOTSTRAP_PROGRESS] 40% - Universal Forwarder package downloaded'

    $Install = Start-Process msiexec.exe -ArgumentList @('/i', $InstallerPath, '/qn', 'AGREETOLICENSE=Yes', "INSTALLDIR=`"$InstallPath`"") -Wait -PassThru
    if ($Install.ExitCode -ne 0) { throw "Universal Forwarder MSI failed with exit code $($Install.ExitCode)." }
    Write-Output '[BOOTSTRAP_PROGRESS] 60% - Universal Forwarder installed'

    New-Item -Path $AppLocal -ItemType Directory -Force | Out-Null
    @"
[tcpout]
defaultGroup = splunk_receiver

[tcpout:splunk_receiver]
server = $($SplunkPrivateIp):9997
useACK = true
"@ | Set-Content -Path (Join-Path $AppLocal 'outputs.conf') -Encoding ASCII

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
'@ | Set-Content -Path (Join-Path $AppLocal 'inputs.conf') -Encoding ASCII
    Write-Output '[BOOTSTRAP_PROGRESS] 80% - forwarder inputs and outputs configured'

    $SplunkExe = Join-Path $InstallPath 'bin\splunk.exe'
    & $SplunkExe start --accept-license --answer-yes --no-prompt
    & $SplunkExe enable boot-start
    Set-Service -Name SplunkForwarder -StartupType Automatic
    Start-Service -Name SplunkForwarder
    Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
    Write-Output '[BOOTSTRAP_COMPLETE] 100% - Windows Universal Forwarder configured'
} catch {
    Write-Error "[BOOTSTRAP ERROR] $_"
    exit 1
} finally {
    Stop-Transcript
}
