# TCG Addressables Crash Patcher

**by Rain**

Fixes the TCG World PC startup hang where `AddressablesManager.CheckAndDownloadContent()` throws a `NullReferenceException` in `AddressablesImpl.GetHashCode(IResourceLocation)` during `DownloadDependenciesAsync` (stuck loading screen).

## Quick start (recommended)

1. Close TCG World completely.
2. Download **`TCG_Addressables_Patcher.exe`** from the [latest release](../../releases/latest).
3. Double-click the EXE.
4. Choose **[1] Apply Patch**.
5. Launch the game again.

You may then see a normal multi-GB content download — that is expected after the catalog spoof.

## What the patch does

- Backs up the cached remote Addressables catalog (`catalog_X.Y.Z.bin` / `.hash`) under `%LocalLow%\TCG World\TCG World PC Build\com.unity.addressables\`.
- Replaces the **catalog bin** with the **built-in** `StreamingAssets\aa\catalog.bin`.
- Leaves the **remote hash** in place so the client does not re-download the broken CDN catalog.
- Supports **Undo / Revert** from the same menu.

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
