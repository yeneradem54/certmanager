<#
.SYNOPSIS
Local CA (Windows ADCS) Entegrasyon Modülü
#>

$ErrorActionPreference = "Stop"

function Invoke-PSCMLocalCACertificateRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter(Mandatory)][System.Security.SecureString]$PfxPass,
        [string]$TemplateName = 'WebServer',
        [string]$FriendlyName
    )
    
    Write-PSCMLog -Level INFO -Message "Local CA (ADCS) uzerinden sertifika talep ediliyor: $Domain (Template: $TemplateName)" -Source 'LocalCA'
    
    $reqArgs = @{
        DnsName = $Domain
        CertStoreLocation = 'cert:\LocalMachine\My'
        Template = $TemplateName
    }
    
    try {
        $certInfo = Get-Certificate @reqArgs
        $cert = $certInfo.Certificate
        
        if (-not $cert) {
            throw "Get-Certificate basarili dondu fakat sertifika nesnesi bulunamadi."
        }
        
        Write-PSCMLog -Level INFO -Message "Sertifika alindi, Thumbprint: $($cert.Thumbprint)" -Source 'LocalCA'
        
        if ($FriendlyName) {
            $cert.FriendlyName = $FriendlyName
        } else {
            $cert.FriendlyName = $Domain
        }
        
        $tempPath = Join-Path $env:TEMP "$([guid]::NewGuid()).pfx"
        
        Write-PSCMLog -Level INFO -Message "Sertifika PFX olarak disari aktariliyor..." -Source 'LocalCA'
        Export-PfxCertificate -Cert $cert -FilePath $tempPath -Password $PfxPass | Out-Null
        
        # Orijinal sertifikayi depodan temizle (Sadece PFX olarak saklamak icin)
        Remove-Item -Path "cert:\LocalMachine\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
        
        return [PSCustomObject]@{
            Thumbprint = $cert.Thumbprint
            NotBefore = $cert.NotBefore.ToString('o')
            NotAfter = $cert.NotAfter.ToString('o')
            Issuer = $cert.Issuer
            PfxTempPath = $tempPath
        }
    } catch {
        Write-PSCMLog -Level ERROR -Message ("Local CA sertifika talebi basarisiz: " + $_.Exception.Message) -Source 'LocalCA'
        throw
    }
}

Export-ModuleMember -Function Invoke-PSCMLocalCACertificateRequest
