# TCG Addressables Crash Patcher

**by Rain**

Fixes the TCG World PC startup hang where `AddressablesManager.CheckAndDownloadContent()` throws a `NullReferenceException` in `AddressablesImpl.GetHashCode(IResourceLocation)` during `DownloadDependenciesAsync` (stuck loading screen).

## Quick start (recommended)

1. Close TCG World completely.
2. Download **`TCG_Addressables_Patcher.exe`** from the [latest release](../../releases/latest).
3. Double-click the EXE.
4. Choose **[1] Apply Patch**.
5. Type **Y** and press Enter when asked to confirm.
6. Launch the game again.

You may then see a normal multi-GB content download — that is expected after the catalog spoof.

## Manual fix (no scripts / no EXE)

Use this if you prefer File Explorer only. **Admin rights are not required.**

### Before you start

1. **Fully close** TCG World and the TCGWorld Launcher (check Task Manager if unsure).
2. You need to open **two folders**:
   - **A — Addressables cache** (files the game downloads/updates):
     ```
     %USERPROFILE%\AppData\LocalLow\TCG World\TCG World PC Build\com.unity.addressables
     ```
   - **B — Built-in game catalog** (ships with the install; path may vary):
     ```
     …\TCG World PC Build_Data\StreamingAssets\aa
     ```
     Common launcher layout example:
     ```
     %USERPROFILE%\Documents\Launcher\Apps\22\Staging\TCG World PC Build_Data\StreamingAssets\aa
     ```
     Tip: In File Explorer’s address bar, paste the `%USERPROFILE%\…` paths and press Enter.  
     If folder B is hard to find: search your PC for `catalog.bin` and open the one under `StreamingAssets\aa` next to your game install (not under LocalLow).

### Apply (temporary workaround)

In **folder A** (`com.unity.addressables`) you should see files like:

- `catalog_0.2.7.bin` and `catalog_0.2.7.hash`  
  (version numbers may differ, e.g. `0.2.5` — use the **highest** version pair you have)

1. **Backup the remote catalog (important)**  
   - Copy `catalog_X.Y.Z.bin` → paste in the same folder → rename the copy to  
     `catalog_X.Y.Z.bin.broken_bak`  
   - Copy `catalog_X.Y.Z.hash` → paste → rename to  
     `catalog_X.Y.Z.hash.broken_bak`

2. **Replace only the `.bin` with the built-in catalog**  
   - In **folder B**, copy `catalog.bin`  
   - In **folder A**, paste it  
   - Delete or rename the existing `catalog_X.Y.Z.bin` (you already have `.broken_bak`)  
   - Rename the pasted `catalog.bin` to exactly:  
     `catalog_X.Y.Z.bin`  
     (same name/version as before, e.g. `catalog_0.2.7.bin`)

3. **Do not change the `.hash` file**  
   Leave `catalog_X.Y.Z.hash` as it is.  
   That keeps the game from re-downloading the broken remote catalog.

4. **Optional cleanup**  
   If you also have an older pair (e.g. `catalog_0.2.5.bin` / `.hash`), you can delete those leftovers.

5. **Launch the game**  
   You should get past the stuck loading screen. A large content download (several GB) afterward can be normal.

### Undo (restore original)

1. Close the game again.
2. In **folder A**:
   - Delete the current `catalog_X.Y.Z.bin`
   - Rename `catalog_X.Y.Z.bin.broken_bak` → `catalog_X.Y.Z.bin`
   - If you have `catalog_X.Y.Z.hash.broken_bak`, rename it back to `catalog_X.Y.Z.hash` (overwrite if needed)

### Checklist

| Step | Do this | Don’t do this |
|------|---------|----------------|
| Backup | Keep `.broken_bak` copies | Skip backup |
| Replace | Only the **`.bin`** from StreamingAssets | Overwrite the **`.hash`** with anything else |
| Hash file | Leave remote `.hash` untouched | Delete `.hash` (may force a bad re-download) |
| Game | Closed while editing | Edit files while the game is running |

### If it still fails

- Confirm the game was fully closed when you edited files.
- Confirm folder B’s `catalog.bin` is from **your** game install’s `StreamingAssets\aa`, not a random file.
- Confirm the renamed file is exactly `catalog_X.Y.Z.bin` (same version as the `.hash`).
- As a last resort, delete everything inside the `com.unity.addressables` folder and relaunch (this re-fetches from CDN and may bring the crash back if the remote catalog is still bad).

## What the patch does

- Backs up the cached remote Addressables catalog (`catalog_X.Y.Z.bin` / `.hash`) under `%LocalLow%\TCG World\TCG World PC Build\com.unity.addressables\`.
- Replaces the **catalog bin** with the **built-in** `StreamingAssets\aa\catalog.bin`.
- Leaves the **remote hash** in place so the client does not re-download the broken CDN catalog.
- Supports **Undo / Revert** from the same menu (EXE/script only).

## Source / rebuild

| File | Purpose |
|------|---------|
| `TCG_Addressables_Patcher.ps1` | Main patcher UI + logic |
| `TCG_Addressables_Patcher.bat` | Double-click launcher for the `.ps1` |
| `build_patcher_exe.ps1` / `.bat` | Rebuild the single-file `.exe` |

```bat
build_patcher_exe.bat
```

Requires Windows PowerShell (built into Windows). No admin rights needed for the patch itself.

## Notes for developers

Proper fix: republish a clean remote Addressables catalog (or null-guard locations in `AddressablesManager`).

## License / disclaimer

Community workaround for a client content-catalog crash. Use at your own risk. Not affiliated with TCG World ownership unless separately authorized.
