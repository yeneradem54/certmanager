# Bu scripti yeni sunucuda çalıştırın - hatanın tam yerini gösterir
# Yönetici olarak çalıştırın!

$ErrorActionPreference = 'Continue'  # Stop değil - hatayı yakala ama devam et

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = Join-Path $here 'Modules\PSCertManager\PSCertManager.psd1'

Write-Host "=== PS-CertManager Hata Teshis Araci ===" -ForegroundColor Cyan
Write-Host ""

# 1. Modul yukleme
Write-Host "[1/5] Modul yukleniyor..." -ForegroundColor Yellow
try {
    Import-Module $manifest -Force -DisableNameChecking -ErrorAction Stop
    Write-Host "     OK - Modul yuklendi." -ForegroundColor Green
} catch {
    Write-Host "     HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Script: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkYellow
    exit 1
}

# 2. Settings okuma
Write-Host "[2/5] Settings okunuyor..." -ForegroundColor Yellow
try {
    $settings = Get-PSSettings
    Write-Host "     OK - Settings tipi: $($settings.GetType().FullName)" -ForegroundColor Green
    Write-Host "     IsConfigured: $($settings.General.IsConfigured)" -ForegroundColor Cyan
} catch {
    Write-Host "     HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Script: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkYellow
    Write-Host "     Stack Trace:" -ForegroundColor Magenta
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
}

# 3. SecretStore Vault
Write-Host "[3/5] SecretStore kontrol ediliyor..." -ForegroundColor Yellow
try {
    $vaultOk = Unlock-PSCMSecretStore -Silent
    Write-Host "     OK - Vault durumu: $vaultOk" -ForegroundColor Green
} catch {
    Write-Host "     HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Script: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkYellow
    Write-Host "     Stack Trace:" -ForegroundColor Magenta
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
}

# 4. Show-PSCMBanner
Write-Host "[4/5] Show-PSCMBanner test ediliyor..." -ForegroundColor Yellow
try {
    Show-PSCMBanner
    Write-Host "     OK - Banner gosterildi." -ForegroundColor Green
} catch {
    Write-Host "     HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Script: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkYellow
    Write-Host "     Stack Trace:" -ForegroundColor Magenta
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
}

# 5. Show-PSCMMenu
Write-Host "[5/5] Show-PSCMMenu test ediliyor..." -ForegroundColor Yellow
try {
    Show-PSCMMenu
    Write-Host "     OK - Menu gosterildi." -ForegroundColor Green
} catch {
    Write-Host "     HATA: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "     Script: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkYellow
    Write-Host "     Stack Trace:" -ForegroundColor Magenta
    Write-Host $_.ScriptStackTrace -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "=== Teshis Tamamlandi ===" -ForegroundColor Cyan
Write-Host "Devam etmek icin bir tusa basin..."
[void][System.Console]::ReadKey($true)
