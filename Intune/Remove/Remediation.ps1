# ============================================================
# Named Local Admin — Intune Remediation
# Action  : REMOVE
# Script  : Remediation
#
# Removes the enrolled Azure AD user from the local Administrators group.
# Runs only when Detection exits 1 (non-compliant).
# ============================================================

function Get-LoggedOnUser {
    # Method 1: Explorer.exe process owner via WMI (PRIMARY — works in SYSTEM context)
    try {
        $explorer = Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop
        foreach ($proc in $explorer) {
            $owner = Invoke-CimMethod -InputObject $proc -MethodName GetOwner
            if ($owner.Domain -eq "AzureAD") {
                return "$($owner.Domain)\$($owner.User)"
            }
        }
    } catch {}

    # Method 2: CIM ComputerSystem
    try {
        $loggedOn = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($loggedOn -like "AzureAD\*") { return $loggedOn }
    } catch {}

    # Method 3: LogonUI registry
    try {
        $logonUI = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" -ErrorAction Stop
        if ($logonUI.LastLoggedOnUser -like "AzureAD\*") { return $logonUI.LastLoggedOnUser }
        if ($logonUI.LastLoggedOnSAMUser -like "AzureAD\*") { return $logonUI.LastLoggedOnSAMUser }
    } catch {}

    # Method 4: Winlogon registry
    try {
        $winlogon = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction Stop
        if ($winlogon.DefaultUserName -like "AzureAD\*") { return $winlogon.DefaultUserName }
    } catch {}

    return $null
}

try {
    $samAccount = Get-LoggedOnUser

    if (-not $samAccount) {
        Write-Output "All methods failed to detect an AzureAD user. Cannot proceed."
        exit 1
    }

    Write-Output "Detected user : $samAccount"

    # Safety check — verify user is actually in the group before attempting removal
    $groupMembers = net localgroup Administrators
    $isAdmin = $groupMembers | Where-Object { $_.Trim() -eq $samAccount.Trim() }

    if (-not $isAdmin) {
        Write-Output "$samAccount is not a local admin. No action needed."
        exit 0
    }

    # Remove from local Administrators
    $result = net localgroup Administrators "$samAccount" /delete 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Output "Successfully removed $samAccount from local Administrators"
        Write-Output "`nCurrent Administrators:"
        net localgroup Administrators
    } elseif ($LASTEXITCODE -eq 2) {
        Write-Output "$samAccount was not a member. No action needed."
    } else {
        Write-Output "net localgroup /delete failed with exit code $LASTEXITCODE : $result"
        exit 1
    }

    exit 0
} catch {
    Write-Output "Remediation failed: $_"
    exit 1
}
