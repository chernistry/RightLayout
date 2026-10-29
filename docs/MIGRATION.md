# Migration Notes Between Major Versions

Guidance for documenting changes that affect users or contributors when moving between major versions of RightLayout.

## When to add notes

Add migration notes for any major release that changes:

- User-visible behavior or defaults
- Permissions, installation, or distribution
- Stored data such as settings, personalization state, or logs
- CLI/REPL commands or integration tests

## Release checklist

1. Update `releases/notes/vX.0.md` before creating the release tag.
2. Include a short "What changed" section and a "Migration notes" section.
3. List any required user actions, such as reinstalling or re-granting permissions.
4. Include one copy-pasteable command for the common verification step.

## Example

For a hypothetical `2.0` release, create the notes file before running the release workflow:

```bash
mkdir -p releases/notes
cat > releases/notes/v2.0.md <<'EOF'
RightLayout 2.0 is a major release.

What changed:
- Updated correction policy behavior.
- Added new defaults for proactive hints.

Migration notes:
- Install the new PKG over the existing app.
- Re-grant Accessibility permission if correction stops working.
- Verify the installed version:
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/RightLayout.app/Contents/Info.plist
EOF
```

## Linking

Link published notes from `README.md` or `CONTRIBUTING.md` so users and contributors can discover the guidance.

Use:

```markdown
[Migration notes for v2.0](releases/notes/v2.0.md)
```

Then verify the link is discoverable:

```bash
grep -n "docs/MIGRATION.md" CONTRIBUTING.md
```
