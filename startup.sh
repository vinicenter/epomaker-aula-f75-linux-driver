#!/usr/bin/env bash

set -u

WIRELESS_RULE_FILE="/etc/udev/rules.d/99-bytech-keyboard.rules"
WIRED_RULE_FILE="/etc/udev/rules.d/99-bytech-keyboard-wired.rules"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DRIVER_DIR="$SCRIPT_DIR/F75"
DRIVER_EXE="$DRIVER_DIR/OemDrv.exe"
DRIVER_ZIP="$SCRIPT_DIR/AULA_F75_Setup_v2.zip"
DRIVER_URL="https://orders.epomaker.com/software/AULA_F75_Setup_v2.zip"

find_driver_exe() {
	if [[ -f "$DRIVER_EXE" ]]; then
		return 0
	fi

	if [[ ! -d "$DRIVER_DIR" ]]; then
		return 1
	fi

	local discovered_exe
	discovered_exe=$(find "$DRIVER_DIR" -type f -iname "OemDrv.exe" | head -n 1)
	if [[ -n "$discovered_exe" ]]; then
		DRIVER_EXE="$discovered_exe"
		return 0
	fi

	return 1
}

cleanup_installer_artifacts() {
	if [[ ! -d "$DRIVER_DIR" ]]; then
		return 0
	fi

	find "$DRIVER_DIR" -maxdepth 1 -type f \( -iname "unins*.exe" -o -iname "unins*.dat" -o -iname "uninstall.dll" \) -delete 2>/dev/null
}

is_inno_installer() {
	local exe_file="$1"

	if ! command -v strings >/dev/null 2>&1; then
		return 1
	fi

	strings -n 20 "$exe_file" 2>/dev/null | grep -q "Inno Setup Setup Data"
}

extract_installer_file() {
	local exe_file="$1"
	local is_inno=false

	mkdir -p "$DRIVER_DIR"

	if is_inno_installer "$exe_file"; then
		is_inno=true
	fi

	if [[ "$is_inno" == true ]] && command -v innoextract >/dev/null 2>&1; then
		echo "Using innoextract to extract..."
		if innoextract --extract --output-dir "$DRIVER_DIR" "$exe_file" >/dev/null 2>&1; then
			cleanup_installer_artifacts
			return 0
		fi
	fi

	if command -v cabextract >/dev/null 2>&1; then
		echo "Using cabextract to extract..."
		if cabextract -d "$DRIVER_DIR" "$exe_file" >/dev/null 2>&1; then
			cleanup_installer_artifacts
			return 0
		fi
	fi

	if command -v unzip >/dev/null 2>&1; then
		echo "Trying unzip to extract..."
		if unzip -o -d "$DRIVER_DIR" "$exe_file" >/dev/null 2>&1; then
			cleanup_installer_artifacts
			return 0
		fi
	fi

	if command -v 7z >/dev/null 2>&1; then
		echo "Trying 7z to extract..."
		if 7z x -y "-o$DRIVER_DIR" "$exe_file" >/dev/null 2>&1; then
			cleanup_installer_artifacts
			return 0
		fi
	fi

	if command -v bsdtar >/dev/null 2>&1; then
		echo "Trying bsdtar to extract..."
		if bsdtar -xf "$exe_file" -C "$DRIVER_DIR" >/dev/null 2>&1; then
			cleanup_installer_artifacts
			return 0
		fi
	fi

	if [[ "$is_inno" == true ]]; then
		if command -v winepath >/dev/null 2>&1; then
			local win_driver_dir
			win_driver_dir=$(winepath -w "$DRIVER_DIR" 2>/dev/null || true)
			if [[ -n "$win_driver_dir" ]]; then
				echo "Trying silent Inno installer execution via Wine..."
				if wine "$exe_file" /SP- /VERYSILENT /SUPPRESSMSGBOXES /NORESTART "/DIR=$win_driver_dir" >/dev/null 2>&1; then
					cleanup_installer_artifacts
					return 0
				fi
			fi
		fi
	fi

	return 1
}

ask_yes_no() {
	local prompt="$1"
	local answer

	while true; do
		read -r -p "$prompt [y/n]: " answer
		case "${answer,,}" in
			y|yes) return 0 ;;
			n|no) return 1 ;;
			*) echo "Please answer with y or n." ;;
		esac
	done
}

check_wine_installed() {
	if ! command -v wine >/dev/null 2>&1; then
		echo "Wine is not installed."
		echo "Install it first, then run this script again."
		echo "Example (Ubuntu/Debian): sudo apt update && sudo apt install -y wine"
		exit 1
	fi
}

select_usb_device_ids() {
	local mode_label="$1"
	local lsusb_output
	local -a lines
	local choice
	local selected_line
	local vid_pid

	if ! lsusb_output="$(lsusb)"; then
		echo "Failed to run lsusb. Make sure usbutils is installed."
		return 1
	fi

	if [[ -z "$lsusb_output" ]]; then
		echo "No USB devices were listed by lsusb."
		return 1
	fi

	echo
	echo "Detected USB devices for $mode_label setup:"
	echo "Tip: look for your keyboard entry in this list (It can be different in your setup):"
	echo "  - Wired: BY Tech Gaming Keyboard"
	echo "  - Wireless: Compx 2.4G Wireless Receiver"
	echo "If unsure, unplug/replug the keyboard or dongle and pick the new line."
	mapfile -t lines <<< "$lsusb_output"
	for i in "${!lines[@]}"; do
		printf '%2d) %s\n' "$((i + 1))" "${lines[$i]}"
	done

	while true; do
		read -r -p "Select the keyboard line number for $mode_label: " choice

		if [[ ! "$choice" =~ ^[0-9]+$ ]] || ((choice < 1 || choice > ${#lines[@]})); then
			echo "Invalid choice. Enter a valid number from the list."
			continue
		fi

		selected_line="${lines[$((choice - 1))]}"
		vid_pid="$(sed -nE 's/.*ID ([0-9a-fA-F]{4}):([0-9a-fA-F]{4}).*/\1 \2/p' <<< "$selected_line")"

		if [[ -z "$vid_pid" ]]; then
			echo "Could not extract vendor/product IDs from selected line."
			echo "Please choose another device."
			continue
		fi

		read -r SELECTED_VENDOR SELECTED_PRODUCT <<< "$vid_pid"
		SELECTED_VENDOR="${SELECTED_VENDOR,,}"
		SELECTED_PRODUCT="${SELECTED_PRODUCT,,}"

		echo "Selected: idVendor=$SELECTED_VENDOR idProduct=$SELECTED_PRODUCT"
		return 0
	done
}

write_udev_rule_file() {
	local rule_file="$1"
	local vendor_id="$2"
	local product_id="$3"

	sudo tee "$rule_file" >/dev/null <<EOF
SUBSYSTEM=="usb", ATTRS{idVendor}=="$vendor_id", ATTRS{idProduct}=="$product_id", MODE="0666"
KERNEL=="hidraw*", ATTRS{idVendor}=="$vendor_id", ATTRS{idProduct}=="$product_id", MODE="0666"
EOF

	echo "Created/updated: $rule_file"
}

reload_udev_rules() {
	sudo udevadm control --reload-rules && sudo udevadm trigger
	echo "udev rules reloaded."
}

setup_wireless() {
	if select_usb_device_ids "wireless"; then
		write_udev_rule_file "$WIRELESS_RULE_FILE" "$SELECTED_VENDOR" "$SELECTED_PRODUCT"
	else
		echo "Skipping wireless setup due to device selection failure."
	fi
}

setup_wired() {
	if select_usb_device_ids "wired"; then
		write_udev_rule_file "$WIRED_RULE_FILE" "$SELECTED_VENDOR" "$SELECTED_PRODUCT"
	else
		echo "Skipping wired setup due to device selection failure."
	fi
}

download_driver() {
	if [[ -f "$DRIVER_ZIP" ]]; then
		echo "Driver zip already exists: $DRIVER_ZIP"
		return 0
	fi

	echo "Downloading F75 driver from official source..."
	echo "URL: $DRIVER_URL"

	if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
		echo "Error: wget or curl not found. Cannot download driver."
		echo "Please download manually from: $DRIVER_URL"
		echo "and place it in: $DRIVER_ZIP"
		return 1
	fi

	if command -v wget >/dev/null 2>&1; then
		wget -q -O "$DRIVER_ZIP" "$DRIVER_URL"
		local wget_status=$?
		if [[ $wget_status -eq 0 ]]; then
			echo "Download successful!"
			return 0
		else
			echo "Download failed with wget (error code: $wget_status)"
			rm -f "$DRIVER_ZIP"
			return 1
		fi
	elif command -v curl >/dev/null 2>&1; then
		curl -L -o "$DRIVER_ZIP" "$DRIVER_URL"
		local curl_status=$?
		if [[ $curl_status -eq 0 ]]; then
			echo "Download successful!"
			return 0
		else
			echo "Download failed with curl (error code: $curl_status)"
			rm -f "$DRIVER_ZIP"
			return 1
		fi
	fi

	return 1
}

try_extract_driver() {
	local exe_file
	exe_file=$(find "$SCRIPT_DIR" -maxdepth 1 -iname "*.exe" -type f | head -n 1)

	if [[ -z "$exe_file" ]]; then
		return 1
	fi

	echo "Found installer: $(basename "$exe_file")"
	echo "Attempting to extract..."

	if extract_installer_file "$exe_file"; then
		echo "Extraction successful!"
		return 0
	fi

	echo "Could not extract with available tools."
	echo "If this is an Inno Setup installer, install innoextract: sudo apt install -y innoextract"
	return 1
}

extract_zip_driver() {
	if [[ ! -f "$DRIVER_ZIP" ]]; then
		return 1
	fi

	echo "Extracting driver from zip file..."
	mkdir -p "$DRIVER_DIR"

	if ! command -v unzip >/dev/null 2>&1; then
		echo "Error: unzip not found. Please install it: sudo apt install -y unzip"
		return 1
	fi

	# Extract zip to temporary location
	unzip -o -d "$DRIVER_DIR" "$DRIVER_ZIP" >/dev/null 2>&1
	if [[ $? -ne 0 ]]; then
		echo "Failed to extract zip file."
		return 1
	fi

	echo "Zip extraction successful!"

	# Now check if there's an .exe file inside and extract it
	local inner_exe
	inner_exe=$(find "$DRIVER_DIR" -maxdepth 1 -iname "*.exe" -type f ! -iname "OemDrv.exe" | head -n 1)

	if [[ -n "$inner_exe" ]]; then
		echo "Found inner installer: $(basename "$inner_exe")"
		echo "Extracting inner installer..."

		if extract_installer_file "$inner_exe"; then
			echo "Inner installer extraction successful!"
			return 0
		fi

		echo "Warning: Could not extract inner installer, but zip extraction succeeded."
		echo "You may need to manually extract: $inner_exe"
		echo "Tip: This installer appears to be Inno Setup. Install innoextract: sudo apt install -y innoextract"
		return 1
	fi

	# If no inner .exe but OemDrv.exe exists, we're good
	if [[ -f "$DRIVER_DIR/OemDrv.exe" ]]; then
		echo "OemDrv.exe found in extracted files!"
		return 0
	fi

	echo "Warning: No OemDrv.exe found in extracted files."
	return 1
}

check_driver_files() {
	if find_driver_exe; then
		return 0
	fi

	if [[ ! -d "$DRIVER_DIR" ]]; then
		echo "F75 driver folder not found."
		echo

		# Try downloading and extracting from official source
		echo "Attempting to download F75 driver from official Epomaker source..."
		if download_driver; then
			if extract_zip_driver; then
				echo "Driver downloaded and extracted successfully!"
				return 0
			fi
		fi

		echo
		echo "Attempting to extract from local .exe installer..."
		if try_extract_driver; then
			echo "Driver extracted successfully!"
			return 0
		fi

		echo
		echo "Error: Could not obtain or extract F75 driver files."
		echo "Please manually download from: $DRIVER_URL"
		echo "and place the zip file in: $DRIVER_ZIP"
		echo "Then run this script again."
		return 1
	fi

	echo "OemDrv.exe not found in $DRIVER_DIR."
	echo "Attempting recovery extraction from existing files..."

	if extract_zip_driver || try_extract_driver; then
		if find_driver_exe; then
			return 0
		fi
	fi

	echo "Error: OemDrv.exe still not found after extraction attempts."
	echo "Please install innoextract and run again: sudo apt install -y innoextract"
	echo "See README.md for instructions."
	return 1

	return 0
}

launch_driver() {
	if ! check_driver_files; then
		return 1
	fi

	echo "Starting driver with Wine: $DRIVER_EXE"
	wine "$DRIVER_EXE"
}

setup_already_done() {
	[[ -f "$WIRELESS_RULE_FILE" && -f "$WIRED_RULE_FILE" ]]
}

run_setup_flow() {
	local did_setup=false

	echo
	if ask_yes_no "Do you want to setup wireless rules? (You can plug in the USB dongle before answering yes!)"; then
		setup_wireless
		did_setup=true
	fi

	echo
	if ask_yes_no "Do you want to setup wired rules? (You can plug in the keyboard via USB before answering yes, dont forget to change the mode to USB.)"; then
		setup_wired
		did_setup=true
	fi

	if [[ "$did_setup" == true ]]; then
		reload_udev_rules
	else
		echo "No udev setup selected."
	fi
}

main() {
	check_wine_installed

	if setup_already_done; then
		echo "Setup already detected (both udev rules exist)."
		echo "1) Open driver"
		echo "2) Redo setup process (delete both udev rules, then setup again)"

		while true; do
			read -r -p "Choose an option [1/2]: " existing_choice
			case "$existing_choice" in
				1)
					launch_driver
					return
					;;
				2)
					echo "Removing existing udev rules..."
					sudo rm -f "$WIRELESS_RULE_FILE" "$WIRED_RULE_FILE"
					run_setup_flow
					launch_driver
					return
					;;
				*)
					echo "Invalid option. Choose 1 or 2."
					;;
			esac
		done
	else
		run_setup_flow
		launch_driver
	fi
}

main "$@"
