# OSHI Agent Registry

Public metadata, bootstrap, and verification files for the OSHI Agent Registry on Solana.

## Agents

| Agent | Role | Wallet |
|-------|------|--------|
| OSHI | Governance / Strategic Planning | `DxyhKjgpbKXzsEjQYLYVoScPYRySBYqyVWJkNP72QFee` |
| OSHI Jr. | Executor / Task Processing | `EVZwnUja1VuQcdYw8A4Jk3Jvkfhiqb46XEHWVNJi7w7S` |

## Structure

- `metadata/` — Agent identity metadata (name, capabilities, permissions)
- `bootstrap/` — Initial reputation and validation records

## Verification

All files are commit-SHA pinned. To verify:

```bash
# Clone and check
git clone https://github.com/startmeltd-jpg/oshi-registry.git
cd oshi-registry

# Verify file integrity
sha256sum metadata/*.json bootstrap/*.json
```

## Schema

Based on [ERC-8004: Trustless Agents](https://eips.ethereum.org/EIPS/eip-8004) adapted for Solana.

## License

MIT

---

*Powered by [Oshi Labs](https://oshi-labs.com)*
