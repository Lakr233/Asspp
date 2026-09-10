# GitHub Actions Auto-Build & Sign Guide

This guide explains how to set up your own fork of Asspp to automatically build, sign, and publish the app using GitHub Actions.

This allows you to:

1.  **Always have the latest version**: The workflow automatically pulls changes from the upstream repository.
2.  **OTA Installation**: Install the app directly on your iPhone via a web link, without a computer.
3.  **Automatic Signing**: Uses your own Apple Developer certificate.

---

## 1. Prerequisites

- **Apple Developer Account**: A paid account is required for creating the necessary certificates and provisioning profiles.
- **Signing Assets**:
  - **Distribution Certificate**: A `.p12` file exported from Keychain Access (with a password).
  - **Provisioning Profile**: An Ad Hoc `.mobileprovision` file that includes your device's UDID.
- **GitHub Account**: To fork the repository and run Actions.

## 2. Fork & Configure Repository

1.  **Fork** the [Asspp repository](https://github.com/Lakr233/Asspp) to your account.
2.  Go to **Settings** -> **Actions** -> **General**.
    - Under "Workflow permissions", select **Read and write permissions**.
    - Click **Save**.
3.  Go to **Settings** -> **Pages**.
    - Under "Build and deployment", set **Source** to **GitHub Actions**.

## 3. Prepare Secrets & Variables

You need to provide your signing keys to GitHub so it can sign the app for you.

### Option A: Automatic Setup (Recommended)

We provide a script to generate the necessary values for you.

1.  Open Terminal and navigate to the project directory.
2.  Run the helper script:

    ```bash
    ./Resources/Scripts/generate.github.action.inputs.sh \
      --p12 /path/to/your/certificate.p12 \
      --p12-password 'your-p12-password' \
      --mobileprovision /path/to/your/profile.mobileprovision
    ```

3.  The script will output a set of Secrets and Variables. You can either:
    - Copy-paste them manually into GitHub Settings.
    - Or use the generated `apply-with-gh.sh` script (requires `gh` CLI tool) to apply them automatically.

### Option B: Manual Setup

Go to **Settings** -> **Secrets and variables** -> **Actions**.

#### Secrets (New Repository Secret)

| Name                              | Value             | Description                                                      |
| :-------------------------------- | :---------------- | :--------------------------------------------------------------- |
| `IOS_CERT_P12_BASE64`             | `[Base64 String]` | The content of your `.p12` file converted to Base64.             |
| `IOS_CERT_PASSWORD`               | `[String]`        | The password for your `.p12` file.                               |
| `IOS_PROVISIONING_PROFILE_BASE64` | `[Base64 String]` | The content of your `.mobileprovision` file converted to Base64. |

_To get Base64 on macOS:_ `base64 -i certificate.p12 | pbcopy`

#### Variables (New Repository Variable)

| Name                | Value            | Description                                                                                                               |
| :------------------ | :--------------- | :------------------------------------------------------------------------------------------------------------------------ |
| `IOS_BUNDLE_ID`     | `wiki.qaq.Asspp` | **Important**: Must match the App ID in your Provisioning Profile.                                                        |
| `IOS_EXPORT_METHOD` | `ad-hoc`         | Usually `ad-hoc`.                                                                                                         |
| `IOS_OTA_BASE_URL`  | _(Optional)_     | If you use a custom domain for GitHub Pages, enter it here (e.g., `https://apps.example.com`). Otherwise, leave it empty. |

## 4. Trigger the Build

1.  Go to the **Actions** tab in your forked repository.
2.  Select the **Upstream Signed iOS Build** workflow on the left.
3.  Click **Run workflow**.
    - You can leave the inputs as default.
4.  Wait for the build to complete (usually 5-10 minutes).

## 5. Install

Once the workflow finishes:

1.  Go to your repository's **Releases** page. You should see a new release.
2.  Open the **Installation Page** on your iPhone (Safari):
    - URL format: `https://<your-username>.github.io/<repo-name>/ios/latest/install.html`
3.  Tap **Install**.

## Troubleshooting

- **"Unable to Verify App"**: Go to iOS Settings -> General -> VPN & Device Management and trust your certificate.
- **Installation waits forever**: Ensure your device's UDID is included in the Provisioning Profile you uploaded.
- **Build fails**: Check the Actions logs. Common errors include mismatched Bundle IDs or expired certificates.

## SAP build prerequisites

SAP authentication requires CMake on the build runner. The workflows install it
when missing. Apple account passwords and verification codes are never needed
at build time. See [SAP_AUTHENTICATION.md](SAP_AUTHENTICATION.md) for build inputs,
protocol checks and third-party licensing.
