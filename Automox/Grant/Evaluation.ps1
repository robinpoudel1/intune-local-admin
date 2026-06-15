# ============================================================
# Named Local Admin — Automox Worklet
# Action  : GRANT
# Script  : Evaluation
#
# Detects whether the enrolled Azure AD user is a local admin.
# Exit 0  = Compliant   (user is already a local admin)
# Exit 1  = Non-Compliant (user is not a local admin — triggers remediation)
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
                Write-Output "Method 1 (Explorer.exe) succeeded"
                return "$($owner.Domain)\$($owner.User)"
            }
        }
    } catch { Write-Output "Method 1 failed: $_" }

    # Method 2: CIM ComputerSystem
    try {
        $loggedOn = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
        if ($loggedOn -like "AzureAD\*") {
            Write-Output "Method 2 (CIM) succeeded"
            return $loggedOn
        }
    } catch { Write-Output "Method 2 failed: $_" }

    # Method 3: LogonUI registry
    try {
        $logonUI = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" -ErrorAction Stop
        if ($logonUI.LastLoggedOnUser -like "AzureAD\*") {
            Write-Output "Method 3 (LogonUI) succeeded"
            return $logonUI.LastLoggedOnUser
        }
        if ($logonUI.LastLoggedOnSAMUser -like "AzureAD\*") {
            Write-Output "Method 3 (LogonUI SAM) succeeded"
            return $logonUI.LastLoggedOnSAMUser
        }
    } catch { Write-Output "Method 3 failed: $_" }

    # Method 4: Winlogon registry
    try {
        $winlogon = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -ErrorAction Stop
        if ($winlogon.DefaultUserName -like "AzureAD\*") {
            Write-Output "Method 4 (Winlogon) succeeded"
            return $winlogon.DefaultUserName
        }
    } catch { Write-Output "Method 4 failed: $_" }

    return $null
}

try {
    $samAccount = Get-LoggedOnUser

    if (-not $samAccount) {
        Write-Output "All methods failed to detect an AzureAD user"
        exit 1
    }

    Write-Output "Detected user : $samAccount"

    $groupMembers = net localgroup Administrators
    $isAdmin = $groupMembers | Where-Object { $_.Trim() -eq $samAccount.Trim() }

    if ($isAdmin) {
        Write-Output "Compliant - $samAccount is already a local admin"
        exit 0
    } else {
        Write-Output "Non-Compliant - $samAccount is not a local admin"
        exit 1
    }
} catch {
    Write-Output "Evaluation error: $_"
    exit 1
}
