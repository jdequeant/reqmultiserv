# ReqMultiServ

![Screenshot](https://github.com/user-attachments/assets/1a8fbeec-eb41-4458-a340-9753191a4571)

Multiserver query runner for MariaDB/MySQL in PowerShell 5 + WPF.  
No install, no admin rights, only `mysql.exe` required.

## Features

- Execute one SQL statement across multiple servers in parallel
- Kill long-running queries
- Live execution grid showing worker states
- Results grid with:
  - Auto-generated columns
  - Client-side filtering
  - Excel-friendly copy rules
- Optional CSV export:
  - Writes directly to disk
  - Avoids UI load
  - Handle very large resultset

## Requirements

- Windows 10/11
- PowerShell 5.x (inbox)
- `mysql.exe` on PATH or specified in config
- Network access to target DBs

_No .NET SDK, no installer, no internet._

## Usage

1. Configure `config.json` first. If missing, copy or adapt `config.json.dist`.
2. Run ReqMultiServ.ps1
3. Select servers
4. Type SQL
5. Run (Ctrl+Enter) or Export CSV
6. Rows either pushed to UI or streamed to CSV
7. Execution grid shows progress
8. Kill if necessary

## Why

Designed for locked-down corporate environments where:
- GUI installers are banned
- DB tooling isn’t allowed
- You get mysql.exe and nothing else

Goal:
maximum utility with minimum footprint.

## License

This project is licensed under the WTFPL — Do What The Fuck You Want To Public License.