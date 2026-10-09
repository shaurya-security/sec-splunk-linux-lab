<powershell>
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$LogPath = 'C:\ProgramData\WindowsEndpointBootstrap.log'
$ComputerName = '${hostname}'
$RestartRequired = $false
Start-Transcript -Path $LogPath -Append

try {
    $S3Bucket = '${s3_bucket}'
    $SplunkPrivateIp = '${splunk_private_ip}'
    $UfS3Uri = 's3://${s3_bucket}/${uf_s3_prefix}/${uf_package_key}'
    $UfPackageKey = '${uf_package_key}'
    $Region = '${aws_region}'
    $AwsExe = (Get-Command aws.exe -ErrorAction SilentlyContinue).Source
    if (-not $AwsExe) { $AwsExe = 'C:\Program Files\Amazon\AWSCLIV2\aws.exe' }
    if (-not (Test-Path $AwsExe -PathType Leaf)) {
        throw 'AWS CLI v2 is required on the Windows AMI to retrieve bootstrap and UF files from S3.'
    }

    $LogUtility = Join-Path $env:ProgramData 'userdata-logs.ps1'
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

    $EndpointScript = Join-Path $env:TEMP 'windows-endpoint.ps1'
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
    if (-not $Downloaded) { throw 'Could not download windows-endpoint.sh from S3.' }

    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $EndpointScript `
        -SplunkPrivateIp $SplunkPrivateIp `
        -UfS3Uri $UfS3Uri `
        -UfPackageKey $UfPackageKey
    if ($LASTEXITCODE -ne 0) { throw "Windows endpoint setup exited with code $LASTEXITCODE." }

    Remove-Item $EndpointScript -Force -ErrorAction SilentlyContinue
    if ($env:COMPUTERNAME -ne $ComputerName) {
        Rename-Computer -NewName $ComputerName -Force
        $RestartRequired = $true
    }
} catch {
    Write-Error "[BOOTSTRAP ERROR] $_"
    exit 1
} finally {
    Stop-Transcript
}

if ($RestartRequired) { Restart-Computer -Force }
</powershell>
