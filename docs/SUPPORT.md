# Support

The Keyboard Project has no public production release yet. For test builds, include the app
version/build, iPhone model, iOS version, whether Full Access is enabled and exact reproduction
steps. Never attach real passwords, private messages or clipboard contents.

## Keyboard does not appear

1. Confirm the host app is installed and opens.
2. Go to Settings → General → Keyboard → Keyboards → Add New Keyboard.
3. Select Keyboard Project, then switch with the globe key.
4. For development builds, confirm Developer Mode and developer-certificate trust.
5. If a Personal Team profile expired, redeploy from Xcode.

## Typing works but clipboard does not

- Accept the retention notice and enable Tap to save.
- Enable Full Access for shared history in the keyboard extension.
- Tap Save current clipboard; merely opening the app/keyboard does not capture anything.
- If iOS denies the paste request, change its paste permission or try the explicit button again.
- After revoking Full Access, history is intentionally hidden until access and coordinated
  storage are available again.

## Reporting bugs

Use a GitHub issue for non-sensitive defects. Search existing issues first and use placeholder
text in screenshots. For security/privacy bugs, use the
[private security advisory form](https://github.com/Srimi1/The-Keyboard-project/security/advisories/new),
not a public issue.

The public App Store listing must use a hosted URL for this page before release.
