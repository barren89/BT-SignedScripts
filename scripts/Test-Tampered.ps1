New-Item -ItemType Directory -Path C:\Temp\NegTest -Force | Out-Null
Set-Location C:\Temp\NegTest
Set-Content -Path .\Test-Tampered.ps1 -Value 'Write-Output "ORIGINAL SIGNED CONTENT"'
$cert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert | Where-Object Thumbprint -eq '99AA2356A4F012528A082FCAB4D77342BC1BB4E4'
Set-AuthenticodeSignature -FilePath .\Test-Tampered.ps1 -Certificate $cert | Format-List Status
(Get-Content .\Test-Tampered.ps1 -Raw).Replace('ORIGINAL SIGNED CONTENT','TAMPERED - ye nahi chalna chahiye') | Set-Content -NoNewline .\Test-Tampered.ps1
Get-AuthenticodeSignature .\Test-Tampered.ps1 | Format-List Status, StatusMessage