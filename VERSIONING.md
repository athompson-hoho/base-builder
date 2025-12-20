# Version Management

This project uses **Semantic Versioning** (X.Y.Z) to track releases:

- **X** (Major): Breaking changes or major new features
- **Y** (Minor): New features that are backwards compatible
- **Z** (Patch): Bug fixes and minor improvements

## Automatic Version Bumping

### GitHub Actions (Recommended - Fully Automatic)

GitHub Actions automatically bumps versions on every push to `main` based on conventional commits.

**How it works:**
1. You push code to GitHub with a conventional commit message
2. GitHub Actions workflow triggers automatically
3. Workflow determines version bump type from commit message
4. Updates version files and commits back to repository
5. Creates a release tag and GitHub Release

**No manual steps required!** Just push your code with a proper commit message.

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/) for automatic version detection:

```
fix: Brief description        → PATCH version (1.0.0 → 1.0.1)
feat: Brief description       → MINOR version (1.0.0 → 1.1.0)
BREAKING CHANGE: Description  → MAJOR version (1.0.0 → 2.0.0)
```

**Examples:**
```bash
git commit -m "fix: Modem detection for non-standard sides"
git commit -m "feat: Add turtle excavation state persistence"
git commit -m "BREAKING CHANGE: Redesigned message protocol"
```

### Local Version Bumping (Optional)

If you want to manually bump versions locally before pushing:

```bash
# Bump patch version (for bug fixes, minor changes)
lua bin/version-bump.lua patch

# Bump minor version (for new features)
lua bin/version-bump.lua minor

# Bump major version (for breaking changes)
lua bin/version-bump.lua major
```

This will:
1. Update `shared/config.lua` with new version
2. Update `manifest.json` with new version
3. Print the new version

Then commit and push:
```bash
git add shared/config.lua manifest.json
git commit -m "chore: Bump version to 1.0.2"
git push
```

**Note:** If you manually bump the version, the GitHub Actions workflow will detect the "Bump version" message and skip automatic bumping to avoid conflicts.

## Version Files

Two files must stay in sync:

- **`shared/config.lua`**: `Config.VERSION = "X.Y.Z"`
- **`manifest.json`**: `"version": "X.Y.Z"`

The version-bump script keeps these in sync automatically.

## Release Checklist

- [ ] All code changes complete and tested
- [ ] Run `lua bin/version-bump.lua [type]`
- [ ] Review updated version in both files
- [ ] Run integration tests
- [ ] Commit with `git commit -m "..."`
- [ ] Tag the release: `git tag v1.0.1`
- [ ] Push changes: `git push && git push --tags`

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.1   | 2025-12-20 | Fix modem detection & module loader environment |
| 1.0.0   | 2025-12-19 | Initial release - 6 epics complete |

---

**Questions?** See `shared/config.lua` and `manifest.json` for current version.
