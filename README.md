# VTScan

🌐 **English** · [Español](README.es.md)

> Check any downloaded file with **VirusTotal** right from the Windows context menu. Right-click → a 🟢🟡🔴 traffic-light notification. No browser, no uploading your file.

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?logo=windows)
![PowerShell](https://img.shields.io/badge/made%20with-PowerShell-5391FE?logo=powershell&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)
![No admin](https://img.shields.io/badge/install-no%20admin-success)
![Languages](https://img.shields.io/badge/languages-EN%20%7C%20ES-blueviolet)

---

## What is it?

You downloaded an `.exe`, an `.msi`, an installer from somewhere, and before
double-clicking you want a quick second opinion. **VTScan** adds an option to the
Windows context menu:

> 🛡️ **Scan with VirusTotal**

It tells you, in a colored notification, how many of VirusTotal's ~70 antivirus
engines flag the file as a threat:

| Color | Meaning |
|:---:|---|
| 🟢 **Clean** | 0 detections |
| 🟡 **Caution** | a few detections (check which ones before trusting it) |
| 🔴 **DANGER** | several detections — don't run it until you investigate |

## How it looks

Right-click any executable → **Scan with VirusTotal**:

![VTScan context menu](docs/menu-contextual.png)

In seconds, a traffic-light notification:

| 🟢 Clean (0/70) | 🟡 Caution (2/68) |
|:---:|:---:|
| ![Clean result](docs/notif-limpio.jpg) | ![Caution result](docs/notif-precaucion.jpg) |

> The screenshots show the Spanish UI; the app is bilingual and follows your
> Windows language (or your manual choice).

## Why it's different

- **It doesn't upload your file.** It computes the **SHA-256** hash locally and
  asks VirusTotal whether it already has a report for that hash. Instant, private,
  and it doesn't burn your quota uploading anything. (Uploading unknown files is
  optional and you enable it yourself.)
- **No browser** for the quick check: the answer arrives as a notification. Want
  the details? One button opens the full report.
- **No administrator rights.** Everything installs under your user (`HKCU`) and
  uninstalls with one click.
- **Bilingual (English / Spanish).** The UI follows your Windows language, or you
  pick it by hand in the Command Center.
- **Your API Key never lands in the repo.** It lives in
  `%APPDATA%\VTScan\config.json`, outside the code.

## Requirements

- Windows 10 / 11 (PowerShell is built in).
- A **free VirusTotal API Key**: sign up at
  [virustotal.com](https://www.virustotal.com), go to your profile → **API Key**.
  No card required. The free tier gives ~4 lookups/min and 500/day — plenty for
  personal use.

## Install

1. Download this repository
   (green **Code → Download ZIP** button, or `git clone`).
2. Right-click **`VTScan-CommandCenter.ps1`** → *Run with PowerShell*.
   > If Windows blocks it, open PowerShell in the folder and run:
   > `powershell -ExecutionPolicy Bypass -File .\VTScan-CommandCenter.ps1`
3. Paste your **API Key** → **Save**.
4. **Install menu**. Done!

Now right-click any executable → **Scan with VirusTotal**.

## Command Center

`VTScan-CommandCenter.ps1` is the settings UI. It lets you:

- Load / change the **API Key**.
- Pick the **language** (Auto / Español / English).
- Adjust the **thresholds** (how many detections turn it 🟡 or 🔴).
- Choose **which extensions** appear in the menu (`.exe`, `.dll`, `.msi`, `.sys`,
  `.bat`, `.ps1`, `.cmd`, `.scr`, and more).
- Enable **automatic upload** of files VT doesn't know (<32 MB).
- **Test a file** instantly, without installing anything.
- **Install / remove** the context menu.

> After changing the language, reopen the Command Center to see it applied and
> click **Install menu** again to refresh the context-menu label.

## How to read the result

A low number isn't always malware: niche software (game mods, emulators, old
tools) often triggers **false positives**.

- 🟢 **0** → you're good.
- 🟡 **1–4** → check *which* engines flag it via the "View on VirusTotal" button.
  If they're minor antivirus with generic names (`Trojan.Generic`,
  `ML.Attribute...`), it's almost always noise.
- 🔴 **5+**, especially if heavyweights agree (Microsoft, Kaspersky, ESET,
  BitDefender) → don't run it until you investigate.

The **"View on VirusTotal"** button opens the full report: which engines flag it,
under what name, and why. In this example, the 2/68 were heuristic detections
(`FileRepMalware`) from minor antivirus — the textbook false-positive pattern:

![Detailed VirusTotal report](docs/reporte-virustotal.jpg)

> VTScan **is not a replacement for an antivirus**. It's a quick second opinion
> before you run something.

## How it works inside

```
Right-click → "Scan with VirusTotal"
        │
        ▼
  SHA-256 of the file (local, nothing is uploaded)
        │
        ▼
  GET api/v3/files/{hash}  ──►  VirusTotal
        │
   ┌────┴─────────────┐
   ▼                  ▼
 known            404 (unknown)
   │                  │
 traffic light   optional: upload <32MB
                       │
                 poll the analysis
                       │
                  ▼  traffic light
```

## Project structure

| File | What it does |
|---|---|
| `VTScan.Core.ps1` | Engine: config, languages, hash, VT lookup, popup, menu registration. |
| `VTScan.ps1` | Entry point fired by the context menu. |
| `VTScan-CommandCenter.ps1` | Graphical settings UI. |
| `config.example.json` | Example configuration. |

## Privacy & security

- Your API Key is stored in `%APPDATA%\VTScan\config.json`, **never** in the repo
  (`.gitignore` already covers it).
- The hash lookup **does not transmit the file**, only its SHA-256 fingerprint.
- The code is plain PowerShell: you can read exactly what it does.

## License

[MIT](LICENSE) — use it, modify it and share it freely.
