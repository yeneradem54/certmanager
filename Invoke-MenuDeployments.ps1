function Invoke-MenuDeployments {
    Show-PSCMBanner
    Write-Host '  --- WEB SUNUCUSU DAGITIM (DEPLOYMENT) SIHIRBAZI ---' -ForegroundColor Yellow
    Write-Host ''
    $defaults = $null
    try { $defaults = Get-PSSettings -Section 'Defaults' -ErrorAction Stop } catch { }
    $defStore = if ($defaults -and $defaults.PSObject.Properties.Name -contains 'StoreName' -and $defaults.StoreName) { $defaults.StoreName } else { 'WebHosting' }
    
    try {
        Initialize-PSCMSQLite
        Import-Module PSSQLite -ErrorAction SilentlyContinue
        $dbPath = Join-Path (Get-PSCMPath -Name State) "pscm.db"
        $deploys = @(Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT * FROM deployments" -ErrorAction SilentlyContinue)
        
        if ($deploys.Count -gt 0) {
            $deploys | Format-Table Id,Domain,Target,ComputerName,SiteName,HostHeader -AutoSize | Out-String -Stream | ForEach-Object { Write-Host $_ }
        } else {
            Write-Host 'Kayitli dagitim (deployment) ayari bulunamadi.' -ForegroundColor DarkGray
        }
        
        Write-Host ''
        Write-Host '  [E] Yeni Kesif / Dagitim Ekle   [S] Kayit Sil' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Enter) Ana Menuye Don' -ForegroundColor DarkGray
        Write-Host ''
        $sel = Read-Host 'Islem'
        switch ($sel.ToUpper()) {
            'E' {
                Write-Host 'Hedef Platform:'
                Write-Host '1) Windows IIS (Baglamalari Otomatik Tarar)'
                Write-Host '2) Nginx (Lokal, Servis Yeniden Baslatma)'
                Write-Host '3) Apache (Lokal, Servis Yeniden Baslatma)'
                $tgtSel = Read-Host 'Seciminiz (1/2/3)'
                
                if ($tgtSel -eq '2' -or $tgtSel -eq '3') {
                    $tgtName = if ($tgtSel -eq '2') { 'Nginx' } else { 'Apache' }
                    $d = Read-Host "Hangi Domain/Sertifika icin bu $tgtName kurulumu yapilsin? (Ornek: app.farlas.com)"
                    if (-not $d) { return }
                    
                    Write-Host 'Sertifika (.crt) ve Private Key (.key) dosyalarinin kaydedilecegi tam yollari girin.' -ForegroundColor Cyan
                    $cOut = Read-Host 'Sertifika (.crt) Hedef Yolu (Orn: C:\nginx\conf\ssl\cert.crt)'
                    $kOut = Read-Host 'Private Key (.key) Hedef Yolu (Orn: C:\nginx\conf\ssl\cert.key)'
                    $sName = Read-Host "Servis Adi (Yeniden baslatilacak Windows servisi. Orn: $tgtName.ToLower())"
                    
                    if (-not $cOut -or -not $kOut -or -not $sName) { Write-Host "Eksik bilgi girildi." -ForegroundColor Red; Pause-PSCM; return }
                    
                    $insert = @"
                    INSERT INTO deployments (Domain, Target, ComputerName, SiteName, HostHeader, StoreLocation, StoreName, DeployUsername)
                    VALUES (@Domain, @Target, NULL, @SiteName, @HostHeader, NULL, NULL, @DeployUsername);
"@
                    $p = @{
                        Domain = $d
                        Target = $tgtName
                        SiteName = $sName
                        HostHeader = "$cOut|$kOut"
                        DeployUsername = $null
                    }
                    Invoke-SqliteQuery -DataSource $dbPath -Query $insert -SqlParameters $p | Out-Null
                    Write-Host "`nDagitim ayari BASARIYLA eklendi! ($tgtName)" -ForegroundColor Green
                }
                elseif ($tgtSel -eq '1') {
                    $loc = Read-Host 'Hedef IIS Sunucusu Yerel mi (Localhost) Uzak mi? [Y/U]'
                    $compName = 'localhost'
                    $cred = $null
                    
                    if ($loc -match '^[Uu]') {
                        $compName = Read-Host 'Uzak Sunucu IP veya Bilgisayar Adi'
                        
                        Write-Host "`nSunucuya erisim ve WinRM baglantisi kontrol ediliyor ($compName)..." -ForegroundColor Cyan
                        if ($compName -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
                            try {
                                $hostEntry = [System.Net.Dns]::GetHostEntry($compName)
                                $compName = $hostEntry.HostName
                                Write-Host "IP adresi cozumlenerek sunucu adi ($compName) olarak guncellendi (WinRM uyumlulugu icin)." -ForegroundColor Yellow
                            } catch {
                                Write-Host "UYARI: IP adresi DNS ile cozumlenemedi. IP uzerinden baglanti sorunu yasanabilir." -ForegroundColor DarkYellow
                            }
                        }
                        
                        try {
                            Test-WSMan -ComputerName $compName -ErrorAction Stop | Out-Null
                        } catch {
                            Write-Host "HATA: Hedef makine adi yanlis, cevrimdisi veya WinRM servisi ulasilamaz durumda ($compName)!" -ForegroundColor Red
                            Write-Host "Detay: $_" -ForegroundColor DarkGray
                            Pause-PSCM; return
                        }
                        
                        Write-Host "`nUzak sunucu ($compName) icin yetkili kimlik bilgisi giriniz..." -ForegroundColor Cyan
                        $cred = $null
                        try {
                            # Once GUI kucuk penceresini acmayi dener
                            $cred = Get-Credential -UserName "$compName\Administrator" -Message "PS-CertManager: Uzak Sunucu ($compName) Baglanti Bilgisi" -ErrorAction Stop
                        } catch {
                            $cred = $null
                        }

                        # Eger GUI acilamazsa veya pencere desteklenmeyen bir ortamdaysa konsoldan sor
                        if (-not $cred) {
                            Write-Host '  (Grafik arayuzu acilamadi veya atlandi, konsoldan giris yapabilirsiniz)' -ForegroundColor DarkGray
                            $credUser = Read-Host "  Kullanici Adi (Orn: DOMAIN\Administrator veya .\Administrator)"
                            if (-not $credUser) { Write-Host 'Kullanici adi bos birakildi, islem iptal edildi.' -ForegroundColor Red; Pause-PSCM; return }
                            $credPass = Read-Host "  Sifre" -AsSecureString
                            $cred = New-Object System.Management.Automation.PSCredential($credUser, $credPass)
                        }
                        if (-not $cred) { Write-Host 'Yetkili bilgisi alinamadi, iptal edildi.' -ForegroundColor Red; Pause-PSCM; return }
                        
                        Write-Host "`nIIS uzerindeki siteler taraniyor ($compName)..." -ForegroundColor Yellow
                        try {
                            $bindings = @(Get-PSCMIISBinding -ComputerName $compName -Credential $cred)
                        } catch {
                            Write-Host "Uzak sunucuya baglanti basarisiz: $_" -ForegroundColor Red
                            Pause-PSCM; return
                        }
                    } else {
                        Write-Host "`nIIS uzerindeki siteler taraniyor (localhost)..." -ForegroundColor Yellow
                        try {
                            $bindings = @(Get-PSCMIISBinding -ComputerName 'localhost')
                        } catch {
                            Write-Host "Hata: $_" -ForegroundColor Red
                            Pause-PSCM; return
                        }
                    }
                    
                    if ($bindings.Count -eq 0) {
                        Write-Host "Bulunan IIS sitesi yok veya erisim basarisiz." -ForegroundColor Red
                        Pause-PSCM; return
                    }
                    
                    if ($loc -match '^[Uu]') {
                        Write-Host ''
                        Write-Host 'Uzak sunucu baglantisi BASARILI!' -ForegroundColor Green
                    }
                    
                    Write-Host "`nBulunan IIS Siteleri ve Baglamalar:" -ForegroundColor Cyan
                    $i = 1
                    foreach ($b in $bindings) {
                        Write-Host ("  {0,2}) Site: {1,-20} | Port: {2,-4} | Host: {3}" -f $i, $b.SiteName, $b.Port, $b.HostHeader)
                        $i++
                    }
                    
                    Write-Host ""
                    $bIdx = Read-Host "Listeden bir site numarasi secin (Iptal icin bos birakin)"
                    if (-not $bIdx -or [int]$bIdx -lt 1 -or [int]$bIdx -gt $bindings.Count) { return }
                    
                    $selected = $bindings[[int]$bIdx - 1]
                    
                    Write-Host "`nSecilen Site: $($selected.SiteName) (Host: $($selected.HostHeader))" -ForegroundColor Green
                    $d = Read-Host 'Hangi Domain/Sertifika icin bu siteye kurulum yapilsin? (Ornek: app.farlas.com veya *.farlas.com)'
                    if (-not $d) { return }
                    
                    if ($loc -match '^[Uu]') {
                        Write-Host ''
                        $saveYn = Read-Host 'Bu hesabi arka plan gorevleri (Task Scheduler) icin guvenli kasaya kaydedeyim mi? [E/H] (Varsayilan: E)'
                        if ($saveYn -match '^[EeYy]' -or $saveYn -eq '') {
                            $secretName = "DeployCred_$compName"
                            Set-PSCMSecret -Name $secretName -Value $cred.Password
                            $path = Join-Path (Get-PSCMPath -Name Config) 'settings.json'
                            $obj = Read-PSCMJson -Path $path
                            if ('Deployment' -notin $obj.PSObject.Properties.Name) {
                                $obj | Add-Member -NotePropertyName 'Deployment' -NotePropertyValue ([PSCustomObject]@{})
                            }
                            $obj.Deployment | Add-Member -NotePropertyName ("User_$compName") -NotePropertyValue $cred.UserName -Force
                            $obj | Write-PSCMJson -Path $path
                            
                            Write-Host ("Hesap '$secretName' adiyla guvenli kasaya kaydedildi.") -ForegroundColor Green
                        }
                    }
                    
                    $insert = @"
                    INSERT INTO deployments (Domain, Target, ComputerName, SiteName, HostHeader, StoreLocation, StoreName, DeployUsername)
                    VALUES (@Domain, @Target, @ComputerName, @SiteName, @HostHeader, @StoreLocation, @StoreName, @DeployUsername);
"@
                    $p = @{
                        Domain = $d
                        Target = 'IIS'
                        ComputerName = if ($compName -ne 'localhost') { $compName } else { $null }
                        SiteName = $selected.SiteName
                        HostHeader = $selected.HostHeader
                        StoreLocation = 'LocalMachine'
                        StoreName = $defStore
                        DeployUsername = if ($compName -ne 'localhost' -and $cred) { $cred.UserName } else { $null }
                    }
                    Invoke-SqliteQuery -DataSource $dbPath -Query $insert -SqlParameters $p | Out-Null
                    Write-Host "`nDagitim ayari BASARIYLA eklendi! (StoreName: $defStore)" -ForegroundColor Green
                } else {
                    Write-Host "Gecersiz secim." -ForegroundColor Red
                    Pause-PSCM; return
                }
            }
            'S' {
                $id = Read-Host 'Silinecek kaydin ID numarasini girin'
                if ($id -match '^\d+$') {
                    Invoke-SqliteQuery -DataSource $dbPath -Query "DELETE FROM deployments WHERE Id = @Id" -SqlParameters @{Id=$id} | Out-Null
                    Write-Host 'Dagitim ayari silindi.' -ForegroundColor Green
                } else {
                    Write-Host 'Gecersiz ID girdiniz.' -ForegroundColor Red
                }
            }
        }
    } catch { Write-Host ("Hata: " + $_.Exception.Message) -ForegroundColor Red }
    Pause-PSCM
}
