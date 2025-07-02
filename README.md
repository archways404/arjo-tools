# arjo-tools

A modular PowerShell setup utility for configuring common settings and installing printers on ARJO machines.

## Quick Start

### THINKSHIELD SCRIPT - PowerShell (Recommended)
```powershell 
iex (irm 'https://raw.githubusercontent.com/archways404/arjo-tools/master/ThinkShield/script1.ps1')
```

### NEW PC SETUP - PowerShell (Recommended)
```powershell
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1")
```

### NEW PC SETUP - From CMD
```cmd
powershell -Command "iex (irm 'https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1')"
```

### NEW PC SETUP - If Execution Policy Is Restricted
```cmd
powershell -ExecutionPolicy Bypass -Command "iex (irm 'https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1')"
```

## Structure

```
arjo-tools/
├── main.ps1               # Main entrypoint script
└── components/
    ├── printers.ps1       # Printer installation functions
    └── power.ps1          # Power configuration functions
```

## Requirements

- Windows PowerShell 5.1+
- Admin privileges recommended (for installing printers and changing power settings)

