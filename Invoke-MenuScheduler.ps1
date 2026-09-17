function Invoke-MenuScheduler {
    Show-PSCMBanner
    Write-Host '  --- YENILEME GOREVI (TASK SCHEDULER) ---' -ForegroundColor Yellow
    Write-Host ''
    try {
        $tasks = @(Get-PSCMRenewalTask)
        if ($tasks.Count -gt 0) {
            $tasks | Format-Table Name,State,LastRunTime,NextRunTime -AutoSize | Out-String -Stream | ForEach-Object { Write-Host $_ }
        } else { Write-Host 'Kayitli gorev yok.' -ForegroundColor DarkGray }
    } catch { Write-Host ('Uyari: ' + $_.Exception.Message) -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  [K] Gorev Kaydet   [I] Simdi Calistir   [S] Gorev Sil' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  Enter) Ana Menuye Don' -ForegroundColor DarkGray
    Write-Host ''
    $sel = Read-Host 'Islem'
    if (-not $sel) { return }
    switch ($sel.ToUpper()) {
        'K' {
            $timeIn = Read-Host 'Yenileme saati (varsayilan 03:00)'
            if (-not $timeIn) { $timeIn = '03:00' }
            
            $currentUser = "$env:USERDOMAIN\$env:USERNAME"
            if ($env:USERDOMAIN -eq $env:COMPUTERNAME) { $currentUser = "$env:USERNAME" }
            $userIn = Read-Host "Gorevin calisacagi kullanici [Varsayilan: $currentUser]"
            $runUser = if ($userIn) { $userIn } else { $currentUser }

            $resetPass = Read-Host 'Kayitli scheduler parolasini degistirmek/yeniden girmek istiyor musunuz? [E/H] (Varsayilan: H)'
            if ($resetPass -match '^[EeYy]') {
                $newPass = Read-Host "$runUser icin yeni parola" -AsSecureString
                if ($newPass -and $newPass.Length -gt 0) {
                    Set-PSCMSecret -Name 'Scheduler.Password' -Value $newPass
                    Write-Host 'Yeni parola vaulta kaydedildi.' -ForegroundColor Green
                }
            }

            $qYn = Read-Host 'Action Queue gorevi de eklensin mi (her 5 dk)? [E/H]'
            $withQ = ($qYn -match '^[EeYy]')
            try {
                if ($withQ) { Register-PSCMRenewalTask -Time $timeIn -RunAsUser $runUser -IncludeActionQueue }
                else { Register-PSCMRenewalTask -Time $timeIn -RunAsUser $runUser }
                Write-Host 'Gorev(ler) basariyla kayit edildi.' -ForegroundColor Green
            } catch { Write-Host ('Hata: ' + $_.Exception.Message) -ForegroundColor Red }
        }
        'I' {
            try { Invoke-PSCMRenewalCycle | Format-Table Domain,OncekiKalanGun,Durum,Hata -AutoSize | Out-String -Stream | ForEach-Object { Write-Host $_ } }
            catch { Write-Host ('Hata: ' + $_.Exception.Message) -ForegroundColor Red }
        }
        'S' {
            try { Unregister-PSCMRenewalTask -IncludeActionQueue -Confirm:$false; Write-Host 'Gorevler silindi.' -ForegroundColor Green }
            catch { Write-Host ('Hata: ' + $_.Exception.Message) -ForegroundColor Red }
        }
    }
    Pause-PSCM
}
