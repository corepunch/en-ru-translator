# Verification

Run `sh test/run_all.sh` with Lua 5.3 or newer.
Set `LUA=texlua` if the TeX Live Lua interpreter is installed instead.
The suite uses the real bundled lexicon and checks both ordinary disk loading
and a restricted file reader like an embedded app uses. The test requires no
network access. The snapshots are authored examples, not runtime data.

For asset provenance, export into a fresh directory and compare the generated
`assets.tsv` and named shards byte-for-byte with the checked-in copies. The
source archives and SHA-256 values are documented in the attribution file.
