#Requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][guid]$AdminObjectId,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [ValidateRange(1, 180)][int]$ValidityDays = 180
)

$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This bootstrap uses Windows DPAPI and filesystem ACLs.' }
if ($AdminObjectId -eq [guid]::Empty) { throw 'Supply the authenticated administrator object ID.' }

$destination = [IO.Path]::GetFullPath($OutputDirectory)
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if ($destination.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $destination.StartsWith($repoRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Credential output must be outside this repository.'
}
if (Test-Path -LiteralPath $destination) {
    throw 'Output directory already exists. Use a new directory; credentials are never overwritten.'
}

# Establish a private directory before writing any credential material.
$directory = New-Item -ItemType Directory -Path $destination
$operatorSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
$systemSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl = Get-Acl -LiteralPath $destination
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($operatorSid)
foreach ($sid in @($operatorSid, $systemSid)) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new(
        $sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $destination -AclObject $acl

$rsa = [Security.Cryptography.RSA]::Create(3072)
$certificate = $null
try {
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=arclight-overcast-entra-management', $rsa,
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $request.CertificateExtensions.Add(
        [Security.Cryptography.X509Certificates.X509KeyUsageExtension]::new(
            [Security.Cryptography.X509Certificates.X509KeyUsageFlags]::DigitalSignature, $true))
    $start = [DateTimeOffset]::UtcNow.AddMinutes(-5)
    $end = [DateTimeOffset]::UtcNow.AddDays($ValidityDays)
    $certificate = $request.CreateSelfSigned($start, $end)
    $password = [Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32))
    $protectedPassword = ConvertTo-SecureString -String $password -AsPlainText -Force | ConvertFrom-SecureString
    [IO.File]::WriteAllBytes((Join-Path $destination 'management.pfx'),
        $certificate.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $password))
    [IO.File]::WriteAllText((Join-Path $destination 'password.dpapi'), $protectedPassword)
    $publicPem = $certificate.ExportCertificatePem()
    [IO.File]::WriteAllText((Join-Path $destination 'management.cer'), $publicPem)

    # These inputs contain public certificate material and identifiers only.
    $publicInputs = @{
        admin_object_id = $AdminObjectId.ToString()
        certificate_pem = $publicPem
        certificate_start_date = $certificate.NotBefore.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        certificate_end_date = $certificate.NotAfter.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    [IO.File]::WriteAllText((Join-Path $destination 'terraform-inputs.json'), ($publicInputs | ConvertTo-Json))
    [PSCustomObject]@{
        PublicInputsPath = Join-Path $destination 'terraform-inputs.json'
        CertificatePath = Join-Path $destination 'management.cer'
        Thumbprint = $certificate.Thumbprint
        ExpiresUtc = $publicInputs.certificate_end_date
    }
}
finally {
    $password = $null
    $protectedPassword = $null
    if ($certificate) { $certificate.Dispose() }
    $rsa.Dispose()
}
