<#
.SYNOPSIS
    IIS Dağıtım Modülü (IIS Deployment Module)
.DESCRIPTION
    Bu modül, PFX formatındaki sertifikaları Windows Certificate Store'a yükler
    ve IIS üzerindeki web sitelerine bağlar (binding).
#>

$ErrorActionPreference = "Stop"

function Write-DeployLog {
    param($Level, $Message)
    if (Get-Command Write-PSCMLog -ErrorAction SilentlyContinue) {
        Write-PSCMLog -Level $Level -Message $Message -Source 'Deployment'
    } else {
        if ($Level -eq 'ERROR') { Write-Error $Message }
        else { Write-Host "[$Level] $Message" }
    }
}

function Install-CertificateToStore {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$PfxFilePath,
        
        [Parameter(Mandatory=$true)]
        [securestring]$PfxPassword,
        
        [Parameter(Mandatory=$false)]
        [string]$StoreName = "WebHosting",
        
        [Parameter(Mandatory=$false)]
        [string]$StoreLocation = "LocalMachine"
    )
    
    try {
        if (-not (Test-Path $PfxFilePath)) {
            throw "PFX dosyası bulunamadı: $PfxFilePath"
        }
        
        $store = New-Object System.Security.Cryptography.X509Certificates.X509Store($StoreName, $StoreLocation)
        $store.Open('ReadWrite')
        
        # PFX yükleme (Exportable ve PersistKeySet flagleri ile)
        $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable -bor 
                 [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bor 
                 [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
                 
        $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
        $cert.Import($PfxFilePath, $PfxPassword, $flags)
        
        $store.Add($cert)
        $store.Close()
        
        # IIS logon session hatasini (0x80070520) asmak icin certutil ile onarim
        $certStore = if ($StoreLocation -eq 'LocalMachine') { 'machine' } else { 'user' }
        & certutil.exe -$certStore -repairstore $StoreName $($cert.Thumbprint) | Out-Null
        
        Write-DeployLog -Level INFO -Message "Sertifika basariyla Store'a eklendi. Thumbprint: $($cert.Thumbprint)"
        return $cert
    }
    catch {
        Write-DeployLog -Level ERROR -Message ("Sertifika Store'a yuklenirken hata olustu: " + $_.Exception.Message)
        throw
    }
}

function Set-IISCertificateBinding {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SiteName,
        
        [Parameter(Mandatory=$true)]
        [string]$Thumbprint,
        
        [Parameter(Mandatory=$false)]
        [string]$HostHeader = "",
        
        [Parameter(Mandatory=$false)]
        [switch]$RequireSNI
    )
    
    try {
        [Reflection.Assembly]::LoadWithPartialName("Microsoft.Web.Administration") | Out-Null
        $sm = New-Object Microsoft.Web.Administration.ServerManager
        $site = $sm.Sites[$SiteName]
        if (-not $site) { throw "IIS Sitesi bulunamadi: $SiteName" }
        
        $binding = $null
        if ($HostHeader) {
            $binding = $site.Bindings | Where-Object { $_.Protocol -eq 'https' -and $_.Host -eq $HostHeader }
        } else {
            $binding = $site.Bindings | Where-Object { $_.Protocol -eq 'https' -and $_.Host -eq "" }
        }
        
        Write-DeployLog -Level INFO -Message "Sertifika IIS Binding'e ekleniyor (ServerManager)..."
        
        if (-not $binding) {
            Write-DeployLog -Level INFO -Message "Yeni HTTPS binding olusturuluyor ($SiteName : $HostHeader)..."
            $binding = $site.Bindings.CreateElement()
            $binding.Protocol = "https"
            $binding.BindingInformation = "*:443:$HostHeader"
            $site.Bindings.Add($binding)
        } else {
            Write-DeployLog -Level INFO -Message "Mevcut HTTPS binding guncelleniyor ($SiteName : $HostHeader)..."
        }
        
        if ($RequireSNI.IsPresent -and $HostHeader) {
            $binding.SetAttributeValue("sslFlags", 1)
        } else {
            $binding.SetAttributeValue("sslFlags", 0)
        }
        
        # Sertifika deposunu kontrol et (WebHosting mi My mi?)
        $storeNameFound = "My"
        if (Test-Path "cert:\LocalMachine\WebHosting\$Thumbprint") { $storeNameFound = "WebHosting" }
        elseif (-not (Test-Path "cert:\LocalMachine\My\$Thumbprint")) { throw "Sertifika bulunamadi: $Thumbprint" }
        
        $binding.CertificateStoreName = $storeNameFound
        
        # Hex string'i byte dizisine cevir
        $hashBytes = new-object byte[] ($Thumbprint.Length / 2)
        for ($i = 0; $i -lt $Thumbprint.Length; $i += 2) {
            $hashBytes[$i/2] = [convert]::ToByte($Thumbprint.Substring($i, 2), 16)
        }
        $binding.CertificateHash = $hashBytes
        
        $sm.CommitChanges()
        
        Write-DeployLog -Level INFO -Message "Sertifika basariyla siteye baglandi."
        return $true
    }
    catch {
        Write-DeployLog -Level ERROR -Message ("IIS Binding guncellenirken hata olustu: " + $_.Exception.Message)
        throw
    }
}

Export-ModuleMember -Function Install-CertificateToStore, Set-IISCertificateBinding
