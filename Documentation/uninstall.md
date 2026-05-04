# Uninstall

To uninstall Scéal manually:

1. Quit Scéal.
2. Delete `Sceal.app` from `/Applications` or wherever it was installed.
3. Delete local app data if you want to remove notes and attachments:

```text
~/Library/Application Support/Sceal/
```

4. Delete app preferences if you want to reset appearance, editor, and backup settings:

```bash
defaults delete com.stevewalsh.sceal
```

5. Delete any backup folders you selected manually. Scéal does not remove user-selected backup destinations when the app is deleted.

Do not delete `~/Library/Application Support/Sceal/` if you want to keep your notes for a future reinstall.
