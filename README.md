# Epomaker Aula F75 Linux Driver Setup (Wine)

Quick setup script for running the F75 Windows driver on Linux with Wine and configuring udev permissions.

## Prerequisites

- `wine`
- `lsusb` (from `usbutils`)
- `sudo` access (required to write udev rules)
- Internet connection (for automatic driver download, or manual download)

Optional (for fallback extraction if automatic download fails):
- `wget` or `curl` (for downloading)
- `unzip` (for extracting the driver zip)
- `cabextract` (for extracting legacy .exe installers)
- `innoextract` (recommended for Inno Setup `.exe` installers)

Example install (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y wine usbutils wget unzip cabextract innoextract p7zip-full libarchive-tools
```

## Getting the Driver

The F75 driver is **automatically downloaded and extracted** from the official Epomaker source on first run!

### How the Automatic Extraction Works

The official Epomaker zip file (`AULA_F75_Setup_v2.zip`) contains a Windows installer (`.exe`), which itself contains the actual driver files. The script handles this **two-level extraction** automatically:

1. **Download**: Fetches `AULA_F75_Setup_v2.zip` from official source
2. **Extract Level 1**: Unzips the downloaded file to `F75/` folder → produces `AULA F75 Setup v2.0 20240509.exe`
3. **Extract Level 2**: Extracts the `.exe` installer using `cabextract` (preferred) or `unzip` (fallback) → produces actual driver files
   - For Inno Setup installers, the script also tries `innoextract`, `7z`, `bsdtar`, and a silent Wine install fallback
4. **Cleanup**: Removes installer artifacts (unins*.exe, unins*.dat, uninstall.dll)
5. **Validate**: Confirms `OemDrv.exe` exists and is ready

**That's it!** No manual extraction needed.

### Quick Start - Let the Script Download & Extract It

Simply run:

```bash
chmod +x startup.sh
./startup.sh
```

The script will:
1. **Automatically download** the official F75 driver zip from Epomaker
2. **Extract Level 1**: Unzip the file (produces .exe installer)
3. **Extract Level 2**: Extract the .exe installer (produces driver files)
4. **Guide you through udev setup**
5. **Launch the driver** with Wine

**That's it!** No manual steps needed (unless the download fails).

### If Download Fails

If automatic download fails (network issues, epomaker URL change, etc.), you have fallback options:

**Option A: Manual Download + Script Extraction (Recommended)**
1. Download manually: https://orders.epomaker.com/software/AULA_F75_Setup_v2.zip
2. Place in the repository root:
   ```
   epomaker-aula-f75-linux-driver/
   ├── AULA_F75_Setup_v2.zip      ← Place here
   ├── startup.sh
   └── README.md
   ```
3. Run: `./startup.sh` (script will extract both levels automatically)

**Option B: Manual Extraction**
If you prefer manual extraction:
1. Extract the zip: `unzip AULA_F75_Setup_v2.zip`
2. Extract the .exe: `cabextract "AULA F75 Setup v2.0 20240509.exe"` (or `unzip` if cabextract unavailable)
3. Move extracted files to `F75/` folder
4. Run: `./startup.sh` (script will skip download/extraction, proceed to udev setup)

### Expected Folder Structure (after extraction)

Once extracted, your `F75/` folder should look like this:

```
epomaker-aula-f75-linux-driver/
├── F75/                          ← Extracted driver folder
│   ├── OemDrv.exe                ← Main driver executable
│   ├── InitSetup.dll
│   ├── Cfg.ini
│   ├── appico.ico
│   ├── Dev/
│   ├── Text/
│   ├── skins/
│   ├── unins000.dat
│   ├── unins000.exe
│   └── uninstall.dll
├── startup.sh
├── README.md
└── .gitignore
```

## Quick Start

From the repository root:

```bash
chmod +x startup.sh
./startup.sh
```

The script will:
- Check if the F75 driver files are properly extracted.
- Guide you through udev rule setup (if needed).
- Launch the driver with Wine.

## What `startup.sh` Does

1. Checks if `wine` is installed.
   - If not installed, it prints a message and exits.
2. Verifies that `F75/OemDrv.exe` exists.
   - If missing, it exits with instructions to extract driver files.
3. Detects whether udev setup is already done (both rule files exist):
   - `/etc/udev/rules.d/99-bytech-keyboard.rules`
   - `/etc/udev/rules.d/99-bytech-keyboard-wired.rules`
4. If already set up, prompts:
   - Open driver, or
   - Redo setup (remove both udev files and run setup again)
5. Asks if you want to configure **wireless** first, then **wired**.
6. For each selected mode:
   - Runs `lsusb`
   - Asks you to choose the keyboard line
   - Extracts `idVendor:idProduct`
   - Writes udev rules using those IDs
7. Reloads udev rules.
8. Starts `F75/OemDrv.exe` with Wine.

## Notes

- Plug in the keyboard in the mode you are configuring before selecting from `lsusb`.
- You may need to unplug/replug the keyboard after udev reload.
- The script updates the rule IDs based on your selected USB devices.
- In this setup, the device names detected are:
  - **Wired keyboard**: "BY Tech Gaming Keyboard"
  - **Wireless**: "Compx 2.4G Wireless Receiver"

## Acknowledgments

Special thanks to the [r/mkindia community](https://www.reddit.com/r/mkindia/comments/1r4olqm/finally_aula_f75_software_working_for_linux/) for the original inspiration and discussion that led to this repository.

## Legal & Licensing

- This repository contains **only the setup scripts and udev configuration guidance**.
- The F75 driver binaries are **proprietary to Epomaker/Bytech** and are not redistributed here.
- Users must obtain the driver files directly from official Epomaker sources.
- This project is **not affiliated with Epomaker**; it is a community effort to guide driver setup on Linux via Wine.
