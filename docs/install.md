# Install RepoHub

RepoHub is a free download from [GitHub Releases](https://github.com/lquainta/RepoHub/releases). It needs **macOS 15 or later** and runs on Apple silicon and Intel Macs. It also needs `git`. If it's missing, macOS offers to install the Command Line Tools the first time RepoHub runs it.

## Download and install

1. Open the [latest release](https://github.com/lquainta/RepoHub/releases/latest) and download `RepoHub-<version>.dmg`.
2. *(Optional)* Check the download against the `.sha256` file next to it:

   ```sh
   cd ~/Downloads
   shasum -a 256 -c RepoHub-<version>.dmg.sha256   # prints "RepoHub-<version>.dmg: OK"
   ```

3. Open the DMG and drag **RepoHub** onto **Applications**.

## First launch

RepoHub is signed ad hoc, not with an Apple Developer ID, so Apple hasn't notarized it. The first time you open it, macOS blocks it with *"RepoHub" Not Opened*. To allow it once:

1. Click **Done** in the dialog. Don't move it to the Trash.
2. Open **System Settings → Privacy & Security** and scroll to **Security**.
3. Next to *"RepoHub" was blocked to protect your Mac*, click **Open Anyway** and confirm with your password or Touch ID.

From then on, RepoHub opens normally.

**From Terminal instead:** remove the quarantine flag that macOS adds to downloads, then open the app:

```sh
xattr -dr com.apple.quarantine /Applications/RepoHub.app
open /Applications/RepoHub.app
```

## Update

Download the new DMG and drag RepoHub onto Applications again, choosing **Replace**. Your folders, groups, and settings are kept. You may need to allow the new version once, as above.

## Uninstall

Quit RepoHub and drag it from Applications to the Trash. To also remove its data:

```sh
rm -rf ~/Library/Application\ Support/RepoHub   # folders, groups, and activity history
defaults delete com.lquainta.RepoHub             # settings
security delete-generic-password -s com.lquainta.RepoHub -a session   # GitHub sign-in, if any
```

## How releases are built

When a release PR from release-please is merged, the **Release** workflow tags the version and publishes the GitHub Release. Its **macOS app** job then runs [`scripts/package-dmg.sh`](../scripts/package-dmg.sh) on a macOS runner and attaches the DMG and its checksum to the release. The script:

- builds the Release configuration for both architectures;
- signs the app ad hoc with the hardened runtime and verifies the signature;
- checks that the app's version matches the tag;
- packages it with a link to Applications and writes the SHA-256.

To build the same DMG locally, run `make dmg` (output in `build/dist/`). To rebuild a past release's DMG, run the **Release** workflow by hand with its tag (for example `v0.2.0`).
