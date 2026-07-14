<#
.SYNOPSIS
    Uzak Sunucu IIS Dağıtım Yöneticisi (Remote Deployment Wrapper)
.DESCRIPTION
    Belirtilen uzak sunucularda IISDeployment modülünü çalıştırarak
    sertifika yükleme ve bağlama (binding) işlemlerini gerçekleştirir.
#>

$ErrorActionPreference = "Stop"

function Invoke-RemoteIISDeployment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory=$true)]
        [string]$PfxFilePath,
        
        [Parameter(Mandatory=$true)]
        [securestring]$PfxPassword,
        
        [Parameter(Mandatory=$true)]
        [string]$SiteName,
        
        [Parameter(Mandatory=$false)]
        [string]$HostHeader = "",
        
        [Parameter(Mandatory=$false)]
        [switch]$RequireSNI,
        
        [Parameter(Mandatory=$false)]
        [pscredential]$Credential
    )

    try {
        Write-Verbose "Uzak sunucuya ($ComputerName) sertifika aktarımı başlıyor..."
        
        # PFX dosyasının uzak sunucuya aktarımı
        $remoteTempPath = "C:\Windows\Temp\$([guid]::NewGuid()).pfx"
        
        $sessionParams = @{
            ComputerName = $ComputerName
        }
        if ($Credential) {
            $sessionParams.Add("Credential", $Credential)
        }

        $session = New-PSSession @sessionParams
        
        Write-Verbose "Sertifika dosyası sunucuya kopyalanıyor..."
        Copy-Item -Path $PfxFilePath -Destination $remoteTempPath -ToSession $session
        
        # Modül script bloğunu uzak sunucuya gönderme
        # Localdeki IISDeployment.psm1 içeriğini okuyarak uzak sunucuda çalıştırıyoruz
        $localModulePath = Join-Path -Path $PSScriptRoot -ChildPath "IISDeployment.psm1"
        $moduleScript = Get-Content -Path $localModulePath -Raw
        
        # Uzak sunucuda doğrudan script bloğu olarak çalışacağı için Export-ModuleMember komutunu temizliyoruz
        $moduleScript = $moduleScript -replace '(?mi)^Export-ModuleMember.*', ''
        
        $scriptBlock = {
            param ($pfxPath, $pfxPass, $siteName, $hostHdr, $reqSNI, $modScript)
            
            # Uzak sunucuda modülü memory'de tanımla (Dot-Sourcing kullanarak mevcut scope'a ekliyoruz)
            . ([scriptblock]::Create($modScript))
            
            # Fonksiyonları çağır
            $cert = Install-CertificateToStore -PfxFilePath $pfxPath -PfxPassword $pfxPass -StoreName "WebHosting" -StoreLocation "LocalMachine"
            
            # SNI parametresini Boolean olarak güvenli şekilde geçiyoruz (-Switch:$bool)
            Set-IISCertificateBinding -SiteName $siteName -Thumbprint $cert.Thumbprint -HostHeader $hostHdr -RequireSNI:$reqSNI
            
            # Geçici dosyayı sil
            Remove-Item -Path $pfxPath -Force -ErrorAction SilentlyContinue
            
            return $cert.Thumbprint
        }
        
        Write-Verbose "Uzak sunucuda işlemler başlatılıyor..."
        $thumbprint = Invoke-Command -Session $session -ScriptBlock $scriptBlock -ArgumentList $remoteTempPath, $PfxPassword, $SiteName, $HostHeader, $RequireSNI.IsPresent, $moduleScript
        
        Remove-PSSession -Session $session
        
        Write-Verbose "Uzak sunucu dağıtımı başarıyla tamamlandı. Thumbprint: $thumbprint"
        return $true
    }
    catch {
        Write-Error "Uzak sunucuya deployment sırasında hata: $_"
        if ($session) { Remove-PSSession -Session $session }
        throw
    }
}

Export-ModuleMember -Function Invoke-RemoteIISDeployment
