#!/bin/bash
set -e

# ─── CONFIG ──────────────────────────────────────────────────────────────────
APP_NAME="YourAppName"
TEAM_ID="YOUR_APPLE_TEAM_ID"
SCHEME="Runner"
# "development"      → Development (Xcode auto-manages profiles) — use for Diawi
# "release-testing"  → Ad Hoc / TestFlight internal (requires manual profiles)
# "app-store"        → App Store submission
EXPORT_METHOD="development"

# Google Drive (rclone)
RCLONE_REMOTE="gdrive"
DRIVE_FOLDER_ID="YOUR_GOOGLE_DRIVE_FOLDER_ID"   # root folder

# Diawi
DIAWI_TOKEN="YOUR_DIAWI_API_TOKEN"
# ─────────────────────────────────────────────────────────────────────────────

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$REPO_ROOT/apps/new_app"
IOS_DIR="$APP_DIR/ios"
WORKSPACE="$IOS_DIR/Runner.xcworkspace"

DATE_LABEL=$(date "+%Y-%m-%d_%H-%M")
YEAR=$(date +"%Y")
MONTH=$(date +"%B")
TIMESTAMP=$(date +"%I-%M-%p")

BUILD_OUTPUT="$APP_DIR/build/release_output"
ARCHIVE_PATH="$BUILD_OUTPUT/${APP_NAME}_${DATE_LABEL}.xcarchive"
EXPORT_PATH="$BUILD_OUTPUT/${APP_NAME}_${DATE_LABEL}_ipa"
EXPORT_OPTIONS_PLIST="$BUILD_OUTPUT/ExportOptions.plist"

APK_DIR="$APP_DIR/build/app/outputs/flutter-apk"
APK_FILE="$APK_DIR/app-armeabi-v7a-release.apk"

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Print helpers ────────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  printf  "  %-44s\n" "$1"
  echo "╚══════════════════════════════════════════════╝"
}
print_step()    { echo -e "  ${CYAN}→${RESET}  $1"; }
print_ok()      { echo -e "  ${GREEN}✓${RESET}  $1"; }
print_skip()    { echo -e "  ${YELLOW}⚠${RESET}  $1"; }
print_error()   { echo -e "  ${RED}✗${RESET}  $1"; }
print_info()    { echo -e "  ${BOLD}ℹ${RESET}  $1"; }
print_success() { echo -e "  ${GREEN}${BOLD}✓ $1${RESET}"; }

# ─── upload_ios_to_diawi ─────────────────────────────────────────────────────
# Uploads the IPA to Diawi using their API and returns a shareable link.
# Args: $1 = absolute path to the .ipa file
upload_ios_to_diawi() {
  local ipa_path="$1"

  print_header "Uploading IPA to Diawi"

  # -- Validate ----------------------------------------------------------------
  if [ ! -f "$ipa_path" ]; then
    print_error "IPA not found: $ipa_path"
    return 1
  fi

  if ! command -v curl &>/dev/null; then
    print_error "curl not found. Install with: brew install curl"
    return 1
  fi

  local ipa_size
  ipa_size=$(du -sh "$ipa_path" | cut -f1)
  print_info "IPA: $(basename "$ipa_path")  ($ipa_size)"
  print_step "Uploading to Diawi..."

  # -- Step 1: Upload IPA and get job token ------------------------------------
  local upload_response
  upload_response=$(curl --silent --fail \
    -F "token=${DIAWI_TOKEN}" \
    -F "file=@${ipa_path}" \
    "https://upload.diawi.com/")

  if [ -z "$upload_response" ]; then
    print_error "No response from Diawi. Check your internet connection."
    return 1
  fi

  local job_token
  job_token=$(echo "$upload_response" | grep -o '"job":"[^"]*"' | cut -d'"' -f4)

  if [ -z "$job_token" ]; then
    print_error "Upload failed. Diawi response: $upload_response"
    return 1
  fi

  print_ok "Upload received. Job token: $job_token"
  print_step "Waiting for Diawi to process the IPA..."

  # -- Step 2: Poll job status until complete ----------------------------------
  local max_attempts=20
  local attempt=0
  local status_code=""
  local diawi_hash=""

  while [ "$attempt" -lt "$max_attempts" ]; do
    sleep 3
    attempt=$((attempt + 1))

    local status_response
    status_response=$(curl --silent --fail \
      "https://upload.diawi.com/status?token=${DIAWI_TOKEN}&job=${job_token}")

    status_code=$(echo "$status_response" | grep -o '"status":[0-9]*' | cut -d':' -f2)

    if [ "$status_code" = "2000" ]; then
      # Success — extract the hash
      diawi_hash=$(echo "$status_response" | grep -o '"hash":"[^"]*"' | cut -d'"' -f4)
      break
    elif [ "$status_code" = "4000" ]; then
      local msg
      msg=$(echo "$status_response" | grep -o '"message":"[^"]*"' | cut -d'"' -f4)
      print_error "Diawi processing failed: $msg"
      return 1
    fi

    print_info "Processing... (attempt $attempt/$max_attempts, status: $status_code)"
  done

  if [ -z "$diawi_hash" ]; then
    print_error "Diawi processing timed out after $((max_attempts * 3)) seconds."
    return 1
  fi

  # -- Step 3: Print the shareable link ----------------------------------------
  local diawi_url="https://i.diawi.com/${diawi_hash}"

  echo ""
  echo "╔══════════════════════════════════════════════╗"
  printf  "  %-44s\n" "Diawi Upload Successful"
  echo "╚══════════════════════════════════════════════╝"
  echo ""
  echo -e "  ${BOLD}IPA Name:${RESET}"
  echo -e "  ${GREEN}$(basename "$ipa_path")${RESET}"
  echo ""
  echo -e "  ${BOLD}Diawi Link:${RESET}"
  echo -e "  ${CYAN}${diawi_url}${RESET}"
  echo ""

  # Copy link to clipboard automatically
  echo "$diawi_url" | pbcopy
  print_ok "Link copied to clipboard"

  DIAWI_URL="$diawi_url"
}

# ─── choose_flavour ──────────────────────────────────────────────────────────
# Prompts user to select dev / prod / uat.
# Sets global: FLAVOUR
choose_flavour() {
  echo ""
  echo -e "  ${BOLD}Choose flavour:${RESET}"
  echo "  0 → dev"
  echo "  1 → prod"
  echo "  2 → uat"
  echo ""
  printf "  Enter choice [0/1/2]: "
  read -r FLAVOUR_CHOICE

  case $FLAVOUR_CHOICE in
    0) FLAVOUR="dev"  ;;
    1) FLAVOUR="prod" ;;
    2) FLAVOUR="uat"  ;;
    *)
      print_error "Invalid flavour choice: \"$FLAVOUR_CHOICE\". Must be 0, 1, or 2."
      exit 1
      ;;
  esac

  print_info "Flavour selected: ${BOLD}$FLAVOUR${RESET}"
}

# ─── validate_rclone ─────────────────────────────────────────────────────────
# Checks rclone is installed and the remote is configured.
validate_rclone() {
  if ! command -v rclone &>/dev/null; then
    print_error "rclone not found. Install with: brew install rclone"
    print_error "Then configure with: rclone config"
    exit 1
  fi

  if ! rclone listremotes 2>/dev/null | grep -q "^${RCLONE_REMOTE}:"; then
    print_error "rclone remote \"${RCLONE_REMOTE}\" not configured."
    print_error "Run: rclone config"
    exit 1
  fi
}

# ─── validate_apk_exists ─────────────────────────────────────────────────────
# Checks the target APK file exists before attempting upload.
validate_apk_exists() {
  if [ ! -f "$APK_FILE" ]; then
    print_error "APK not found at: $APK_FILE"
    print_error "Run the Android build first."
    exit 1
  fi
  local size
  size=$(du -sh "$APK_FILE" | cut -f1)
  print_ok "APK found: app-armeabi-v7a-release.apk  ($size)"
}

# ─── ensure_drive_folder_exists ──────────────────────────────────────────────
# Creates a folder inside the Drive root if it does not already exist.
# Args: $1 = relative path inside the root (e.g. "RuConnect/dev/2026/May")
ensure_drive_folder_exists() {
  local folder_path="$1"

  # rclone lsf lists directory contents; if the folder exists the command
  # succeeds (even if empty). We suppress output — we only care about exit code.
  if rclone lsf "${RCLONE_REMOTE}:${folder_path}" \
       --drive-root-folder-id "$DRIVE_FOLDER_ID" \
       &>/dev/null; then
    print_info "Folder exists:  ${folder_path}"
  else
    print_step "Creating folder: ${folder_path}"
    rclone mkdir "${RCLONE_REMOTE}:${folder_path}" \
      --drive-root-folder-id "$DRIVE_FOLDER_ID"
    print_ok "Created: ${folder_path}"
  fi
}

# ─── generate_drive_link ─────────────────────────────────────────────────────
# Retrieves a shareable Google Drive URL for the uploaded file using rclone link.
# Args:    $1 = full rclone path (e.g. "RuConnect/dev/2026/May/file.apk")
# Outputs: sets global UPLOADED_URL (empty string on failure — non-fatal)
generate_drive_link() {
  local remote_path="$1"
  UPLOADED_URL=""

  print_step "Generating shareable Drive URL..."

  local raw_url
  if raw_url=$(rclone link \
      "${RCLONE_REMOTE}:${remote_path}" \
      --drive-root-folder-id "$DRIVE_FOLDER_ID" \
      2>/dev/null); then
    # rclone link may return an "open" sharing URL; strip trailing whitespace
    UPLOADED_URL=$(echo "$raw_url" | tr -d '[:space:]')
    print_ok "Drive URL generated"
  else
    print_skip "Could not generate Drive URL (file may need manual sharing enabled)."
    print_skip "You can still access it via Google Drive at the path shown below."
  fi
}

# ─── upload_android_apk ──────────────────────────────────────────────────────
# Builds the Drive destination path, ensures all folders exist, uploads,
# then calls generate_drive_link to produce a shareable URL.
# Requires: FLAVOUR, YEAR, MONTH, TIMESTAMP to be set.
upload_android_apk() {
  print_header "Uploading APK to Google Drive"

  validate_rclone
  validate_apk_exists

  # ── Build destination path ──────────────────────────────────────────────────
  local dest_folder="${FLAVOUR}/${YEAR}/${MONTH}"
  local apk_name="${APP_NAME}_${MONTH}_${YEAR}_${TIMESTAMP}.apk"
  local dest_path="${dest_folder}/${apk_name}"

  print_info "Destination : ${RCLONE_REMOTE}:${dest_path}"
  print_info "Root folder : ${DRIVE_FOLDER_ID}"
  echo ""

  # ── Ensure folder hierarchy exists ─────────────────────────────────────────
  ensure_drive_folder_exists "${FLAVOUR}"
  ensure_drive_folder_exists "${FLAVOUR}/${YEAR}"
  ensure_drive_folder_exists "${FLAVOUR}/${YEAR}/${MONTH}"

  # ── Upload ───────────────────────────────────────────────────────────────────
  echo ""
  print_step "Uploading: ${apk_name}"

  if ! rclone copyto "$APK_FILE" "${RCLONE_REMOTE}:${dest_path}" \
        --drive-root-folder-id "$DRIVE_FOLDER_ID" \
        --progress; then
    print_error "Upload failed. Check your rclone config and internet connection."
    exit 1
  fi

  # ── Generate shareable URL (non-fatal if it fails) ──────────────────────────
  echo ""
  generate_drive_link "${dest_path}"

  # ── Print upload summary ─────────────────────────────────────────────────────
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  printf  "  %-44s\n" "Upload completed successfully"
  echo "╚══════════════════════════════════════════════╝"
  echo ""
  echo -e "  ${BOLD}APK Name:${RESET}"
  echo -e "  ${GREEN}${apk_name}${RESET}"
  echo ""
  echo -e "  ${BOLD}Google Drive Path:${RESET}"
  echo -e "  ${CYAN}${RCLONE_REMOTE}:${dest_path}${RESET}"
  echo ""
  if [ -n "$UPLOADED_URL" ]; then
    echo -e "  ${BOLD}Google Drive URL:${RESET}"
    echo -e "  ${CYAN}${UPLOADED_URL}${RESET}"
  else
    echo -e "  ${YELLOW}Google Drive URL: not available (see warning above)${RESET}"
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════════════════════
# INTERACTIVE PROMPTS
# ══════════════════════════════════════════════════════════════════════════════

BUILD_ANDROID=false
BUILD_IOS=false
UPLOAD_TO_DRIVE=false
FLAVOUR=""

echo ""
echo -e "  ${BOLD}What do you want to build?${RESET}"
echo "  1) Android only"
echo "  2) iOS only"
echo "  3) Both Android + iOS"
echo ""
printf "  Enter choice [1/2/3]: "
read -r CHOICE

case $CHOICE in
  1) BUILD_ANDROID=true ;;
  2) BUILD_IOS=true ;;
  3) BUILD_ANDROID=true; BUILD_IOS=true ;;
  *)
    print_error "Invalid choice. Exiting."
    exit 1
    ;;
esac

if $BUILD_ANDROID; then
  echo ""
  printf "  Upload APK to Google Drive? [y/N]: "
  read -r UPLOAD_CHOICE
  case $UPLOAD_CHOICE in
    y|Y|yes|YES)
      UPLOAD_TO_DRIVE=true
      choose_flavour
      ;;
  esac
fi

mkdir -p "$BUILD_OUTPUT"

# ══════════════════════════════════════════════════════════════════════════════
# CLEANUP — delete previous build artifacts before building
# ══════════════════════════════════════════════════════════════════════════════
if $BUILD_ANDROID; then
  if [ -d "$APK_DIR" ]; then
    print_header "Cleaning Android build output"
    print_step "Removing old APKs from: $APK_DIR"
    rm -f "$APK_DIR"/*.apk
    print_ok "Old APKs deleted"
  fi
fi

if $BUILD_IOS; then
  if [ -d "$BUILD_OUTPUT" ]; then
    print_header "Cleaning iOS build output"
    print_step "Removing old archives and IPAs from: $BUILD_OUTPUT"
    rm -rf "$BUILD_OUTPUT"/*.xcarchive
    rm -rf "$BUILD_OUTPUT"/*_ipa
    rm -f  "$BUILD_OUTPUT"/ExportOptions.plist
    print_ok "Old iOS artifacts deleted"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# ANDROID — flutter build apk --split-per-abi
# ══════════════════════════════════════════════════════════════════════════════
if $BUILD_ANDROID; then
  print_header "Android APK  ($DATE_LABEL)"

  cd "$APP_DIR"
  print_step "Running: flutter build apk --split-per-abi"
  flutter build apk --split-per-abi
  cd "$REPO_ROOT"

  echo ""
  echo "  Output APKs:"
  for key in "arm64-v8a" "armeabi-v7a" "x86_64"; do
    src="$APK_DIR/app-${key}-release.apk"
    if [ -f "$src" ]; then
      size=$(du -sh "$src" | cut -f1)
      print_ok "app-${key}-release.apk  ($size)"
    else
      print_skip "app-${key}-release.apk not found"
    fi
  done

  if $UPLOAD_TO_DRIVE; then
    upload_android_apk
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# iOS — xcodebuild archive + export IPA
# ══════════════════════════════════════════════════════════════════════════════
if $BUILD_IOS; then
  print_header "iOS IPA  ($DATE_LABEL)"

  # -- 1. flutter build ios (no codesign — xcodebuild handles signing) ---------
  print_step "Running: flutter build ios --release --no-codesign"
  cd "$APP_DIR"
  flutter build ios --release --no-codesign
  cd "$REPO_ROOT"

  # -- 2. Write ExportOptions.plist --------------------------------------------
  print_step "Writing ExportOptions.plist  (method: $EXPORT_METHOD)"
  cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>${EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>thinning</key>
  <string>&lt;thin-for-all-variants&gt;</string>
</dict>
</plist>
PLIST

  # -- 3. Archive --------------------------------------------------------------
  print_step "Archiving  →  $ARCHIVE_PATH"
  xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=iOS" \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    | xcpretty --simple 2>/dev/null || true

  if [ ! -d "$ARCHIVE_PATH" ]; then
    echo ""
    print_error "Archive failed. Re-running without xcpretty for full output:"
    xcodebuild archive \
      -workspace "$WORKSPACE" \
      -scheme "$SCHEME" \
      -configuration Release \
      -archivePath "$ARCHIVE_PATH" \
      -destination "generic/platform=iOS" \
      CODE_SIGN_STYLE=Automatic \
      DEVELOPMENT_TEAM="$TEAM_ID"
    exit 1
  fi
  print_ok "Archive created"

  # -- 4. Export IPA -----------------------------------------------------------
  print_step "Exporting IPA  →  $EXPORT_PATH"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
    | xcpretty --simple 2>/dev/null || true

  IPA_FILE=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
  if [ -z "$IPA_FILE" ]; then
    echo ""
    print_error "Export failed. Re-running without xcpretty:"
    xcodebuild -exportArchive \
      -archivePath "$ARCHIVE_PATH" \
      -exportPath "$EXPORT_PATH" \
      -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"
    exit 1
  fi

  IPA_SIZE=$(du -sh "$IPA_FILE" | cut -f1)
  print_ok "IPA ready  ($IPA_SIZE)  →  $IPA_FILE"

  # -- 5. Upload IPA to Diawi --------------------------------------------------
  DIAWI_URL=""
  upload_ios_to_diawi "$IPA_FILE"
fi

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
print_header "Build complete"
if $BUILD_ANDROID; then
  print_ok "Android APKs  →  $APK_DIR"
  if $UPLOAD_TO_DRIVE; then
    print_ok "Drive path    →  ${FLAVOUR}/${YEAR}/${MONTH}/${APP_NAME}_${MONTH}_${YEAR}_${TIMESTAMP}.apk"
    if [ -n "$UPLOADED_URL" ]; then
      print_ok "Drive URL     →  $UPLOADED_URL"
    fi
  fi
fi
if $BUILD_IOS; then
  print_ok "iOS IPA   →  $EXPORT_PATH"
  if [ -n "$DIAWI_URL" ]; then
    print_ok "Diawi URL →  $DIAWI_URL"
  fi
fi
echo ""
