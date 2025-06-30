# arjo-tools

A modular PowerShell setup utility for configuring common settings and installing printers on ARJO machines.

## Quick Start

### PowerShell (Recommended)
```powershell
iex (irm "https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1")
```

### From CMD
```cmd
powershell -Command "iex (irm 'https://raw.githubusercontent.com/archways404/arjo-tools/master/main.ps1')"
```

### If Execution Policy Is Restricted
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

