# Flutter Release Automation Script

A single Bash script that automates the complete Android and iOS release workflow for Flutter applications.

## Why I Built This

Distributing mobile builds for QA, Product Managers, clients, or stakeholders often involves multiple manual steps:

* Build Android APKs
* Locate generated artifacts
* Upload files to cloud storage
* Generate shareable links
* Build iOS archive
* Export IPA
* Upload IPA to a distribution platform
* Wait for processing
* Generate installation links
* Share links with QA

These tasks are repetitive, time-consuming, and prone to human error.

This script transforms the entire workflow into a single command:

```bash
./scripts/build_release.sh
```

---

# Features

## Platform Selection

Choose what you want to build:

```text
1) Android only
2) iOS only
3) Both Android + iOS
```

This allows developers to generate only the artifacts they need.

---

## Build Category Selection

For Android uploads, the script allows selecting a category:

```text
0 → dev
1 → prod
2 → uat
```

These categories are **not Flutter flavors** and do not affect application configuration, bundle IDs, API environments, or build behavior.

The selection is used solely to determine where the generated APK should be uploaded within Google Drive.

Example:

```text
dev/
uat/
prod/
```

This keeps build artifacts organized without requiring manual folder management.

---

# Android Workflow

## Build APKs

The script automatically executes:

```bash
flutter build apk --split-per-abi
```

Generated artifacts:

```text
app-arm64-v8a-release.apk
app-armeabi-v7a-release.apk
app-x86_64-release.apk
```

Benefits:

* Smaller APK sizes
* Device-specific optimization
* Faster downloads
* Easier distribution

---

## Automatic Cleanup

Before building, previous APKs are removed automatically to ensure only fresh artifacts exist.

This prevents confusion when sharing builds.

---

# Google Drive Integration

The script uses Rclone to upload Android builds directly to Google Drive.

## Automatic Folder Organization

Uploads are automatically organized using:

```text
category/
└── year/
    └── month/
        └── build.apk
```

Example:

```text
uat/
└── 2026/
    └── June/
        └── MyApp_June_2026_10-45-AM.apk
```

No manual folder creation is required.

The script creates missing folders automatically.

---

## Automatic Share Link Generation

After uploading:

```bash
rclone link
```

is used to generate a shareable URL.

Example:

```text
https://drive.google.com/file/d/xxxxxxxx/view
```

This link can immediately be shared with:

* QA Teams
* Product Managers
* Stakeholders
* Clients

---

# iOS Workflow

## Flutter iOS Build

The script automatically runs:

```bash
flutter build ios --release --no-codesign
```

to generate iOS release artifacts.

---

## Archive Creation

Uses:

```bash
xcodebuild archive
```

to generate:

```text
MyApp.xcarchive
```

---

## IPA Export

Uses:

```bash
xcodebuild -exportArchive
```

to generate:

```text
MyApp.ipa
```

---

## Automatic Code Signing

Supports automatic signing through Xcode:

```bash
CODE_SIGN_STYLE=Automatic
```

along with:

```bash
DEVELOPMENT_TEAM="your_apple_team_id"
```

No manual Xcode interaction is required during the release process.

---

# Diawi Integration

After the IPA is generated, the script automatically uploads it to Diawi.

## Upload Process

The workflow:

1. Upload IPA
2. Receive Diawi Job ID
3. Poll processing status
4. Wait for completion
5. Generate installation URL

Example:

```text
https://i.diawi.com/your_generated_hash
```

This allows testers to install builds directly on their devices.

---

## Automatic Clipboard Support

Once the upload completes:

```bash
pbcopy
```

copies the generated Diawi link directly to the clipboard.

The link can instantly be pasted into:

* Slack
* Microsoft Teams
* Jira
* Email
* WhatsApp
* Telegram

No manual copy-paste required.

---

# Build Output Cleanup

Before every build, old artifacts are automatically removed:

### Android

```text
Old APKs deleted
```

### iOS

```text
Old Archives deleted
Old IPA exports deleted
```

This ensures every build starts from a clean state.

---

# Required Tools

## Flutter

```bash
flutter --version
```

---

## Xcode

```bash
xcodebuild -version
```

---

## Rclone

Install:

```bash
brew install rclone
```

Configure:

```bash
rclone config
```

Create a Google Drive remote:

```text
your_remote_name
```

---

## Diawi Account

Create an account:

https://www.diawi.com

Generate an API Token:

```text
Dashboard
→ API Access
→ Generate Token
```

---

# Configuration

Before using the script, replace the following placeholders:

```bash
APP_NAME="your_app_name"

TEAM_ID="your_apple_team_id"

RCLONE_REMOTE="your_remote_name"

DRIVE_FOLDER_ID="your_google_drive_folder_id"

DIAWI_TOKEN="your_diawi_api_token"
```

Never commit sensitive credentials to a public repository.

For production environments, store credentials using environment variables or CI/CD secrets.

---

# Example Usage

Run:

```bash
./scripts/build_release.sh
```

Choose:

```text
3) Both Android + iOS
```

Select upload category:

```text
uat
```

The script will:

✓ Build Android APKs

✓ Upload APK to Google Drive

✓ Generate shareable Drive URL

✓ Build iOS Archive

✓ Export IPA

✓ Upload IPA to Diawi

✓ Generate Installation URL

✓ Copy URL to Clipboard

✓ Display build summary

---

# Benefits

## Faster Distribution

Reduces build-sharing time from:

```text
15–20 minutes
```

to:

```text
2–3 minutes
```

---

## Consistent Release Process

Every developer follows the same workflow.

No undocumented release steps.

---

## Reduced Human Error

Prevents:

* Missing uploads
* Wrong file sharing
* Forgotten archive exports
* Missing installation links

---

## Improved Team Productivity

QA and stakeholders receive builds faster.

Developers spend less time on repetitive release tasks.

---

# Ideal For

* Flutter Teams
* Mobile Development Teams
* Internal QA Distribution
* UAT Testing
* Client Review Builds
* Startups
* Agencies
* Teams without dedicated DevOps resources

---

# Technologies Used

* Flutter
* Bash
* Rclone
* Google Drive API
* Diawi API
* Xcodebuild
* Curl
* pbcopy

---

# Final Result

One command.

One workflow.

Android APKs automatically uploaded to Google Drive.

iOS IPAs automatically uploaded to Diawi.

Shareable links generated automatically.

Ready for QA, UAT, stakeholder review, and internal distribution with minimal manual effort.
