function Get-PSCertificate {
<#
.SYNOPSIS
Kayitli sertifikalari (metadata) listeler.
#>
    [CmdletBinding()]
    param(
        [string]$Domain,
        [ValidateSet('Healthy','Warning','Critical','Expired','All')][string]$Status = 'All'
    )
    $listRaw = @(Get-PSCMState -Table 'certificates')
    if ($listRaw.Count -eq 0) { return @() }
    $now = (Get-Date).ToUniversalTime()
    $threshold = 30
    try {
        $certSet = Get-PSSettings -Section 'Certificate'
        if ($certSet -and $certSet.PSObject.Properties.Name -contains 'RenewalThresholdDay') {
            $threshold = [int]$certSet.RenewalThresholdDay
        }
    } catch { }
    $enriched = New-Object System.Collections.Generic.List[object]
    foreach ($c in $listRaw) {
        if ($null -eq $c) { continue }
        $props = @($c.PSObject.Properties.Name)
        $domVal = $null
        if ($props -contains 'Domain') { $domVal = [string]$c.Domain }
        if (-not $domVal) { continue }
        $wcVal = $false
        if ($props -contains 'Wildcard') { $wcVal = [bool]$c.Wildcard }
        $issuer = "Let's Encrypt"
        if ($props -contains 'Issuer' -and $c.Issuer) { $issuer = [string]$c.Issuer }
        $thumb = ''
        if ($props -contains 'Thumbprint') { $thumb = [string]$c.Thumbprint }
        $nb = $null; $na = $null
        if ($props -contains 'NotBefore') { $nb = $c.NotBefore }
        if ($props -contains 'NotAfter')  { $na = $c.NotAfter }
        $fr = $domVal
        if ($props -contains 'FriendlyName' -and $c.FriendlyName) { $fr = [string]$c.FriendlyName }
        $pathVal = ''
        if ($props -contains 'Path' -and $c.Path) { $pathVal = [string]$c.Path }
        $expire = $null
        if ($na) { try { $expire = [datetime]$na } catch { $expire = $null } }
        $days = -1
        if ($expire) { $days = [int]($expire - $now).TotalDays }
        $st = 'Healthy'
        if ($expire) {
            if ($days -lt 0) { $st = 'Expired' }
            elseif ($days -le 7) { $st = 'Critical' }
            elseif ($days -le $threshold) { $st = 'Warning' }
        }
        $provider = 'ACME'
        if ($props -contains 'Provider' -and $c.Provider) { $provider = [string]$c.Provider }
        
        $enriched.Add([PSCustomObject]@{
            Domain=$domVal; Wildcard=$wcVal; Issuer=$issuer; Thumbprint=$thumb
            NotBefore=$nb; NotAfter=$na; DaysRemaining=$days; Status=$st
            FriendlyName=$fr; Path=$pathVal; Provider=$provider
        })
    }
    $out = $enriched.ToArray()
    if ($Domain) { $out = @($out | Where-Object { $_.Domain -like $Domain }) }
    if ($Status -ne 'All') { $out = @($out | Where-Object { $_.Status -eq $Status }) }
    return ,$out
}
