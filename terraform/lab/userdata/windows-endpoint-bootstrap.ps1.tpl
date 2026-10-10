<powershell>
# Endpoint setup hash: ${windows_endpoint_hash}
# Diagnostic helper hash: ${logs_hash}
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$SocLabDir = 'C:\Soc-Lab'
$SocLabConfigDir = Join-Path $SocLabDir 'config'
$SocLabLogDir = Join-Path $SocLabDir 'logs'
$SocLabPackageDir = Join-Path $SocLabDir 'packages'
New-Item -Path $SocLabConfigDir, $SocLabLogDir, $SocLabPackageDir -ItemType Directory -Force | Out-Null

$ProfilePath = $PROFILE
$ProfileDirectory = Split-Path -Parent $ProfilePath
New-Item -Path $ProfileDirectory -ItemType Directory -Force | Out-Null
if (-not (Test-Path $ProfilePath)) { New-Item -ItemType File -Path $ProfilePath -Force | Out-Null }
$ProfileLine = "Set-Location '$SocLabDir'"
if (-not (Select-String -Path $ProfilePath -Pattern $ProfileLine -SimpleMatch -Quiet -ErrorAction SilentlyContinue)) {
    Add-Content -Path $ProfilePath -Value $ProfileLine
}

$LogPath = Join-Path $SocLabLogDir 'WindowsEndpointBootstrap.log'
$ComputerName = '${hostname}'
$RestartRequired = $false
Start-Transcript -Path $LogPath -Append

try {
    Write-Output '[BOOTSTRAP_PROGRESS] 0% - Windows endpoint bootstrap started'
    $S3Bucket = '${s3_bucket}'
    $SplunkPrivateIp = '${splunk_private_ip}'
    $UfS3Uri = 's3://${s3_bucket}/${uf_s3_prefix}/${uf_package_key}'
    $UfPackageKey = '${uf_package_key}'
    $Region = '${aws_region}'

    $AwsExe = (Get-Command aws.exe -ErrorAction SilentlyContinue).Source
    if (-not $AwsExe) {
        $AwsExe = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
    }
    if (-not (Test-Path $AwsExe -PathType Leaf)) {
        Write-Output '[BOOTSTRAP_PROGRESS] 5% - AWS CLI missing; downloading official AWS CLI v2 installer'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $AwsMsiPath = Join-Path $SocLabPackageDir 'AWSCLIV2.msi'
        $AwsMsiUri = 'https://awscli.amazonaws.com/AWSCLIV2.msi'
        $AwsMsiDownloaded = $false
        for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
            try {
                Invoke-WebRequest -Uri $AwsMsiUri -OutFile $AwsMsiPath -UseBasicParsing
                if (Test-Path $AwsMsiPath -PathType Leaf) {
                    $AwsMsiDownloaded = $true
                    break
                }
            } catch {
                Write-Output "AWS CLI download attempt $Attempt failed: $_"
                Start-Sleep -Seconds 5
            }
        }
        if (-not $AwsMsiDownloaded) { throw 'Could not download AWS CLI v2 installer from awscli.amazonaws.com.' }

        $Signature = Get-AuthenticodeSignature -FilePath $AwsMsiPath
        if ($Signature.Status -ne 'Valid') {
            throw "AWS CLI installer signature is not valid (status: $($Signature.Status))."
        }
        $AwsInstall = Start-Process msiexec.exe -ArgumentList @('/i', "`"$AwsMsiPath`"", '/qn', '/norestart') -Wait -PassThru
        if ($AwsInstall.ExitCode -notin @(0, 3010)) {
            throw "AWS CLI v2 MSI installation failed with exit code $($AwsInstall.ExitCode)."
        }
        $AwsExe = Join-Path $env:ProgramFiles 'Amazon\AWSCLIV2\aws.exe'
    }
    if (-not (Test-Path $AwsExe -PathType Leaf)) {
        throw "AWS CLI v2 is still not available at '$AwsExe' after installation."
    }
    Write-Output "[BOOTSTRAP_PROGRESS] 10% - AWS CLI is available at $AwsExe"

    $LogUtility = Join-Path $SocLabDir 'userdata-logs.ps1'
    $LogUtilityS3Uri = "s3://$S3Bucket/userdata-logs.ps1"
    $LogUtilityDownloaded = $false
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        & $AwsExe s3 cp $LogUtilityS3Uri $LogUtility --region $Region
        if ($LASTEXITCODE -eq 0 -and (Test-Path $LogUtility -PathType Leaf)) {
            $LogUtilityDownloaded = $true
            break
        }
        Start-Sleep -Seconds 5
    }
    if (-not $LogUtilityDownloaded) { throw 'Could not download userdata-logs.ps1 from S3.' }
    Write-Output '[BOOTSTRAP_PROGRESS] 20% - diagnostic helper saved in C:\Soc-Lab'

    $EndpointScript = Join-Path $SocLabDir 'windows-endpoint-setup.ps1'
    $ScriptS3Uri = "s3://$S3Bucket/windows-endpoint.sh"
    $Downloaded = $false
    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
        & $AwsExe s3 cp $ScriptS3Uri $EndpointScript --region $Region
        if ($LASTEXITCODE -eq 0 -and (Test-Path $EndpointScript -PathType Leaf)) {
            $Downloaded = $true
            break
        }
        Start-Sleep -Seconds 5
    }
    if (-not $Downloaded) { throw 'Could not download windows-endpoint.sh into C:\Soc-Lab.' }
    Write-Output '[BOOTSTRAP_PROGRESS] 30% - forwarder setup script saved in C:\Soc-Lab'

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EndpointScript `
        -SplunkPrivateIp $SplunkPrivateIp `
        -UfS3Uri $UfS3Uri `
        -UfPackageKey $UfPackageKey
    if ($LASTEXITCODE -ne 0) { throw "Windows endpoint setup exited with code $LASTEXITCODE." }
    Write-Output '[BOOTSTRAP_PROGRESS] 85% - Universal Forwarder configured'

    if ($env:COMPUTERNAME -ne $ComputerName) {
        Rename-Computer -NewName $ComputerName -Force
        $RestartRequired = $true
    }
    Write-Output '[BOOTSTRAP_PROGRESS] 95% - hostname configured'
    if ($RestartRequired) {
        Write-Output '[BOOTSTRAP_COMPLETE] 100% - Windows endpoint configured; restarting to apply hostname'
    } else {
        Write-Output '[BOOTSTRAP_COMPLETE] 100% - Windows endpoint bootstrap completed'
    }
} catch {
    Write-Error "[BOOTSTRAP ERROR] $_"
    exit 1
} finally {
    Stop-Transcript
}

if ($RestartRequired) { Restart-Computer -Force }
</powershell>
