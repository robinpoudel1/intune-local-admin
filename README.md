# Named Local Admin — Intune & Automox

Scalable, owner-scoped PowerShell scripts for dynamically granting and revoking **Named Local Administrator** rights to the enrolled/logged-on user of a device — without hardcoding usernames or relying on third-party agents beyond your chosen management platform.

Supports both **Microsoft Intune Remediations** and **Automox Worklets**.

---

## The Problem

Most approaches to granting local admin in Intune or Automox require you to hardcode a username inside the policy or script. This doesn't scale — every new user or device needs a new policy.

These scripts dynamically detect **who the enrolled owner of the device is** at runtime and grant or revoke local admin rights for that specific user only. New devices are handled automatically with no manual intervention.

---

## How It Works

Each script uses a multi-method detection chain to reliably identify the logged-on Azure AD user across different execution environments (32-bit/64-bit, SYSTEM context, varying registry states):

```
Method 1 → Explorer.exe process owner via WMI    (most reliable in SYSTEM context)
Method 2 → CIM Win32_ComputerSystem UserName
Method 3 → LogonUI registry key
Method 4 → Winlogon registry key
```

Once the user is detected, `net localgroup` is used to check membership and add/remove the user — avoiding PowerShell module dependencies that break in 32-bit environments.

---

## Repository Structure

```
named-local-admin/
│
├── Intune/
│   ├── Grant/
│   │   ├── Detection.ps1       # Remediations detection script
│   │   └── Remediation.ps1     # Remediations remediation script
│   └── Remove/
│       ├── Detection.ps1
│       └── Remediation.ps1
│
├── Automox/
│   ├── Grant/
│   │   ├── Evaluation.ps1      # Worklet evaluation code
│   │   └── Remediation.ps1     # Worklet remediation code
│   └── Remove/
│       ├── Evaluation.ps1
│       └── Remediation.ps1
│
└── README.md
```

---

## Prerequisites

| Requirement | Detail |
|---|---|
| Device join type | Entra ID Joined (Azure AD Joined) |
| OS | Windows 10 1903+ or Windows 11 |
| User account type | Azure AD (`AzureAD\Username`) |
| Intune | Remediations require Intune P1 or above |
| Automox | Any plan with Worklets support |

> ⚠️ Hybrid Joined devices may require adjustments to the user detection logic depending on how accounts are registered.

---

## Intune Setup

### Grant Local Admin

1. Go to **Intune Admin Center → Devices → Remediations → + Create**
2. Fill in a name e.g. `Remediation - Grant Named Local Admin`
3. Under **Settings**:

| Setting | Value |
|---|---|
| Detection script | Contents of `Intune/Grant/Detection.ps1` |
| Remediation script | Contents of `Intune/Grant/Remediation.ps1` |
| Run using logged-on credentials | **No** |
| Run script in 64-bit PowerShell | **Yes** |

4. Assign to a **Device Group**
5. Set schedule to **Every 1 hour** for self-healing

### Remove Local Admin

Repeat the steps above using scripts from `Intune/Remove/` instead.

> ⚠️ Do not assign both Grant and Remove remediations to the same device at the same time — they will conflict.

---

## Automox Setup

### Grant Local Admin

1. Go to **Automox → Worklets → Create Worklet**
2. Set **OS** to `Windows`
3. Paste contents of `Automox/Grant/Evaluation.ps1` into **Evaluation Code**
4. Paste contents of `Automox/Grant/Remediation.ps1` into **Remediation Code**
5. Assign to your target device group
6. Set a recurring schedule for self-healing

### Remove Local Admin

Repeat the steps above using scripts from `Automox/Remove/` instead.

---

## Exit Code Logic

### Grant Scripts

| Exit Code | Meaning |
|---|---|
| `0` | Compliant — user is already a local admin, no action taken |
| `1` | Non-compliant — user is not a local admin, remediation triggered |

### Remove Scripts

| Exit Code | Meaning |
|---|---|
| `0` | Compliant — user is not a local admin, no action taken |
| `1` | Non-compliant — user is still a local admin, remediation triggered |

---

## Self-Healing Behaviour

Because the detection script runs on a schedule, these worklets/remediations are **self-healing**:

- **Grant**: If someone manually removes the user from local admins, the next scheduled run re-adds them
- **Remove**: If someone manually re-adds the user to local admins, the next scheduled run removes them again

---

## Important Notes

- Scripts run as **SYSTEM** — no local admin rights required on the device
- `net localgroup` is used instead of `Get-LocalGroupMember` for compatibility with 32-bit PowerShell environments (e.g. Automox)
- If no user is logged in when the script runs, all detection methods will return null and the script exits cleanly without making changes — it will self-correct on the next run
- The built-in local `Administrator` account is never touched by these scripts

---

## Contributing

Contributions, issues, and feature requests are welcome. Please open an issue or submit a pull request.

---

## License

MIT License — free to use, modify, and distribute.
