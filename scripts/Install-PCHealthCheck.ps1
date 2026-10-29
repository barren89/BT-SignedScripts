<#
.SYNOPSIS
  Installs Microsoft Windows PC Health Check with MSI signature and registry verification.
.DESCRIPTION
  Windows PowerShell 5.1 compatible. Run elevated. Use -NoLaunch for RMM deployment.
  Exit 0 for installed/already installed; 3010 for successful install requiring reboot;
  1 for failure. Does not reboot.
#>
[CmdletBinding()]
param([switch]$NoLaunch)

$ErrorActionPreference = 'Stop'
$DownloadUrl = 'https://aka.ms/GetPCHealthCheckApp'
$MsiPath = Join-Path $env:TEMP 'WindowsPCHealthCheckSetup.msi'
$LogPath = Join-Path $env:TEMP 'PCHealthCheck_install.log'

function Get-PCHealthCheckInstallation {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -eq 'Windows PC Health Check' } |
        Select-Object -First 1)
}

function Get-PCHealthCheckExe {
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
    $relativePaths = @(
        'PCHealthCheck\PCHealthCheck.exe',
        'PCHC\PCHealthCheck.exe',
        'PCHealthCheck\WindowsPCHealthCheck.exe',
        'PCHC\WindowsPCHealthCheck.exe'
    )
    foreach ($root in $roots) {
        foreach ($relative in $relativePaths) {
            $candidate = Join-Path $root $relative
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script as Administrator.'
    }

    $installed = @(Get-PCHealthCheckInstallation)
    $rebootRequired = $false

    if ($installed.Count -gt 0) {
        Write-Output "STATUS | ALREADY_INSTALLED | Version=$($installed[0].DisplayVersion)"
    }
    else {
        Write-Output 'STATUS | DOWNLOADING | Source=Microsoft'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $DownloadUrl -OutFile $MsiPath -UseBasicParsing
        if (-not (Test-Path -LiteralPath $MsiPath -PathType Leaf) -or (Get-Item -LiteralPath $MsiPath).Length -lt 1MB) {
            throw 'Download failed or MSI is unexpectedly small.'
        }

        $sig = Get-AuthenticodeSignature -FilePath $MsiPath
        if ($sig.Status -ne 'Valid' -or -not $sig.SignerCertificate -or
            $sig.SignerCertificate.Subject -notmatch '(^|,)\s*(CN|O)=Microsoft\b') {
            throw "Microsoft installer signature verification failed: $($sig.Status)"
        }
        Write-Output 'STATUS | INSTALLER_SIGNATURE_VALID | Publisher=Microsoft'

        $arguments = "/i `"$MsiPath`" /qn /norestart /L*v `"$LogPath`""
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        $exitCode = [int]$process.ExitCode
        Write-Output "STATUS | MSI_EXIT | Code=$exitCode | Log=$LogPath"
        if ($exitCode -notin @(0,3010)) {
            throw "MSI installation failed (exit code $exitCode). Review $LogPath"
        }
        $rebootRequired = ($exitCode -eq 3010)

        $installed = @(Get-PCHealthCheckInstallation)
        if ($installed.Count -eq 0) {
            throw "MSI returned $exitCode but Windows PC Health Check was not registered in Uninstall registry. Review $LogPath"
        }
        Write-Output "STATUS | INSTALLED | Version=$($installed[0].DisplayVersion)"
    }

    if (-not $NoLaunch) {
        $exe = Get-PCHealthCheckExe
        if ($exe) {
            Start-Process -FilePath $exe
            Write-Output "STATUS | LAUNCHED | Path=$exe"
        }
        else {
            Write-Warning 'Installation is registered, but the executable was not found in standard paths. Launch skipped; no installation failure inferred.'
            Write-Output 'STATUS | LAUNCH_SKIPPED | Reason=ExecutableNotLocated'
        }
    }
    if ($rebootRequired) {
        Write-Output 'SUMMARY | SUCCESS_REBOOT_REQUIRED'
        exit 3010
    }
    Write-Output 'SUMMARY | SUCCESS'
    exit 0
}
catch {
    Write-Error "SUMMARY | FAILED | $($_.Exception.Message)"
    exit 1
}
finally {
    if (Test-Path -LiteralPath $MsiPath -PathType Leaf) {
        Remove-Item -LiteralPath $MsiPath -Force -ErrorAction SilentlyContinue
    }
}

# SIG # Begin signature block
# MIIHZgYJKoZIhvcNAQcCoIIHVzCCB1MCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD6KgHKb+8B7ewl
# 2rtGqXw8VprpKLSD8oyEtPcbnNG8bKCCBEAwggQ8MIICpKADAgECAhBDA1VhSiwW
# t0QqvJJBo74xMA0GCSqGSIb3DQEBCwUAMDYxNDAyBgNVBAMMK0JhcnJlbiBUZWNo
# bm9sb2dpZXMgUG93ZXJTaGVsbCBDb2RlIFNpZ25pbmcwHhcNMjYxMDAyMTcyNjA1
# WhcNMzExMDAyMTczNjA1WjA2MTQwMgYDVQQDDCtCYXJyZW4gVGVjaG5vbG9naWVz
# IFBvd2VyU2hlbGwgQ29kZSBTaWduaW5nMIIBojANBgkqhkiG9w0BAQEFAAOCAY8A
# MIIBigKCAYEAs3MEzwUzAODyNkSq6GyzUBHoBtV8iohjjm+xIOwtR058c5/hsKP0
# cGL1V/lvQNeoqY/71yTkvy/rBaY6RKGNCejsMSaAzUlOmv32+/0haGka1uMAm5VF
# KkE8JGh2D/InGJDk8yu8wrmRIFuC7LYuOyXY20m7kswzvUVsfK/cwCANCDtTp4nN
# efOqrIs4/IK8gaypY+nhKmXPzmrZq6Pcf01rSke5GOLfiMzmP8UzZIOqjqTIFRzH
# jIc9HljAzJPDtTwGGqfvC62ZMNLQ+27gjyh6SWXtR3eJbfaHivsGt+BiNmTlHkxN
# enfLaWm9m6A6ztvifU3l6bk7DefsY/3fGH8l9VjhFqHFU6e5s3RR/j1I9ptD8k8Y
# H5YalyLq2hm0CQ9Kp+xgRSEVL0+QR9OlqaWS8Ye1LFRIU6RVEVmG+RGBMeGuILQq
# ZzptYX8PRHiyYd7xXOwTKe0wYGHy7+47Vst0P7e+fhMiYhkgo8A3oUS1pJ09FjPD
# kbd6wxUEOXyFAgMBAAGjRjBEMA4GA1UdDwEB/wQEAwIHgDATBgNVHSUEDDAKBggr
# BgEFBQcDAzAdBgNVHQ4EFgQU1qiBFPJlSCFvgLVDP2Jf4kvFYDwwDQYJKoZIhvcN
# AQELBQADggGBAHcqyrrzTFv3jSLWOLfrVsN8Q63olZ8Auws67SOfB0t/PNjnCKZB
# ZVN6MxrC8mR5wW9haMRR/Klr+Y1r8NfZHKltu45HlyZh0lBTF2cvE2sQJgUb6+5h
# ZTMPkhDBZKfvut7Li9nMGRyW63++1AQbggfTPSM2mwa57vlVv6nZuinODsQAXaRq
# DQFrZEq+BeZR6B/Vl5XJkJ/lmFjPJNIIXCFL4Tmvoa/5zJXX6n+A9YlkQsE/EbUW
# L1L2UT9xQahP7ziWfGGuaAuHR+a7l1eh+BngIdy8oVvgfAu8EFJffj9IJklK9/Rf
# 9MWF+GYlo8eBZ0jiVkMrudjjZexdynBoahE/C217wM6RyEOSSqbsbY9nhSPwXUpw
# cgidXVk+HrGnDnGptekAFXKvl+gU6Rt8GVAzL6jhnLzcuIPa7onw2CfrtLlBPtea
# xeqMeH9Ut5G5lE9IQuihGwAzLoqUU0PndmfKeTwX1nxfT4nhrVTODIVjF/UYIhZZ
# ESUSzNqTjyE2XjGCAnwwggJ4AgEBMEowNjE0MDIGA1UEAwwrQmFycmVuIFRlY2hu
# b2xvZ2llcyBQb3dlclNoZWxsIENvZGUgU2lnbmluZwIQQwNVYUosFrdEKrySQaO+
# MTANBglghkgBZQMEAgEFAKCBhDAYBgorBgEEAYI3AgEMMQowCKACgAChAoAAMBkG
# CSqGSIb3DQEJAzEMBgorBgEEAYI3AgEEMBwGCisGAQQBgjcCAQsxDjAMBgorBgEE
# AYI3AgEVMC8GCSqGSIb3DQEJBDEiBCDMkOQaVNLlH0BhtoyXbPamIVkj5axWg713
# BUAVJUFB2TANBgkqhkiG9w0BAQEFAASCAYBkrQDhcx/zo0ibW3FdB9/3BqXwoZnv
# WDn7QIoMwx4bDbsEJ1LvNPvYWGV1ObinICkwd42lRSiFBIfsR6RWjXt/N+ltjnRJ
# 43/kyI4ky7W2iSF9Qu4yXdhQKT7Xpxow7hpVIkYSix50XRdR4cp8Jjrika8m/Nej
# xmUeD1w2z91J8un+sEJFxGJrSgw+2pdYAnxZCx/qED5Xik/6BeIP2VAlGacT3hJI
# w12AlWA4qxHpvDiLSqjXnnvjaSmIu1VKjBblP37k5CaWBtbRUzETkw3L792Yz2Ss
# 0LUmO28qy8ipUSY3qdPNUzmesqDjHZlJ7jXyu3jH3RY2jfSRC2YSdu3P0rYh2mTK
# /Xg17og5pGFWtfSXAR7C1kZ1vjauVU/uj1dKcyGo2jIrX7z9uqQHZ5pUZH5jDb/h
# 0IE/zaRT44SUaTl+ei9uAPfvgK4JEKrfQQEJLdYn4JzSra4sjrUkIOAVR4Q3xSrV
# g1cj3fza5gD4pTExO/Bq2Hc2hmKgLaKIyow=
# SIG # End signature block
