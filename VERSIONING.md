# Version Management

This project uses **Semantic Versioning** (X.Y.Z) to track releases:

- **X** (Major): Breaking changes or major new features
- **Y** (Minor): New features that are backwards compatible
- **Z** (Patch): Bug fixes and minor improvements

## Automatic Version Bumping

### Quick Start

Before committing code changes (except version bumps), run:

```bash
# Bump patch version (for bug fixes, minor changes)
lua bin/version-bump.lua patch

# Bump minor version (for new features)
lua bin/version-bump.lua minor

# Bump major version (for breaking changes)
lua bin/version-bump.lua major

# Auto-detect from commit message (default)
lua bin/version-bump.lua
```

This will:
1. Update `shared/config.lua` with new version
2. Update `manifest.json` with new version
3. Print the new version

Then commit normally:

```bash
git add shared/config.lua manifest.json bin/version-bump.lua
git commit -m "Fix: [your message]"
```

### Recommended Workflow

1. **Make your code changes**
2. **Run version bump**:
   ```bash
   lua bin/version-bump.lua patch  # for bug fixes
   ```
3. **Commit with descriptive message**:
   ```bash
   git commit -m "Fix: Module loader environment isolation (v1.0.1)"
   ```

### Automatic Git Hook (Optional - Git Bash only)

For automated versioning on every commit, you can install a pre-commit hook:

```bash
# Make the hook executable
chmod +x .git/hooks/pre-commit

# Copy the provided hook (or create your own)
cp hooks/pre-commit.sh .git/hooks/pre-commit
```

The hook will automatically bump the patch version before each commit unless the commit message contains:
- `Bump version` - Skip versioning (already a version commit)
- `BREAKING CHANGE:` - Bump major version
- `feat:` - Bump minor version
- Otherwise - Bump patch version

### Commit Message Format (Conventional Commits)

While not required, following this format helps with automated tools:

```
fix: Brief description
Minor improvements or bug fixes → Bumps PATCH version

feat: Brief description
New features → Bumps MINOR version

BREAKING CHANGE: Description
API changes or incompatible updates → Bumps MAJOR version
```

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
