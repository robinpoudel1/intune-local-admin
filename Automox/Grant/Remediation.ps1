# ============================================================
# Named Local Admin — Automox Worklet
# Action  : GRANT
# Script  : Remediation
#
# Adds the enrolled Azure AD user to the local Administrators group.
# Runs only when Evaluation exits 1 (non-compliant).
#
# Note: Uses net localgroup and CIM/WMI exclusively for compatibility
#       with Automox's 32-bit PowerShell execution environment.
# ============================================================

function Get-LoggedOnUser {
    # Method 1: Explorer.exe process owner via WMI (PRIMARY — works in 32-bit SYSTEM context)
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

    # Safety check — verify not already admin before adding
    $groupMembers = net localgroup Administrators
    $isAdmin = $groupMembers | Where-Object { $_.Trim() -eq $samAccount.Trim() }

    if ($isAdmin) {
        Write-Output "$samAccount is already a local admin. No action needed."
        exit 0
    }

    # Add to local Administrators
    $result = net localgroup Administrators "$samAccount" /add 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Output "Successfully added $samAccount to local Administrators"
        Write-Output "`nCurrent Administrators:"
        net localgroup Administrators
    } elseif ($LASTEXITCODE -eq 2) {
        Write-Output "$samAccount is already a member. No action needed."
    } else {
        Write-Output "net localgroup /add failed with exit code $LASTEXITCODE : $result"
        exit 1
    }

    exit 0
} catch {
    Write-Output "Remediation failed: $_"
    exit 1
}
