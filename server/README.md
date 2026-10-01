# Local BeamMP test server

A real BeamMP server (v3.9.3, Lua 5.3) in Docker, running the plugin straight from this repo.
The repo's `Resources/` folder is mounted into the container, so there's nothing to copy.

Docker Desktop's CLI lives in `~/.docker/bin`. If `docker` isn't found, run
`export PATH="$HOME/.docker/bin:$PATH"` (or add that line to `~/.zshrc`).

From the repo root:

| What | Command |
|---|---|
| Start (builds the image the first time) | `docker compose -f server/compose.yaml up -d --build` |
| Watch the console | `docker compose -f server/compose.yaml logs -f` |
| Reload after editing `main.lua` or rebuilding `topgear.zip` | `docker compose -f server/compose.yaml restart` |
| Stop | `docker compose -f server/compose.yaml down` |
| Syntax-check with the server's exact Lua (5.3) | `docker run --rm --entrypoint luac5.3 -v "$PWD:/repo:ro" topgear-beammp -p /repo/Resources/Server/TopGear/main.lua` |

## Joining from the game

The server is private (not in the BeamMP server list). In BeamMP, use **Direct Connect** with this
Mac's LAN IP and port `30814`. Find the IP with `ipconfig getifaddr en0`. If macOS asks whether to
allow incoming connections for Docker, allow it.

## Notes

- **AuthKey:** BeamMP won't start without one, so a placeholder is used. The server still runs
  privately; the backend just refuses the key. For a real key (free, from
  https://keymaster.beammp.com), create `server/.env` with `BEAMMP_AUTH_KEY=<key>` (git-ignored).
- **Files the plugin writes:** `config.json` (git-ignored) and `courses.json` (tracked) appear in
  `Resources/Server/TopGear/`. Courses you build on this server therefore land in the repo - commit
  them when you want to keep them. `Resources/Client/mods.json` is written by BeamMP (git-ignored).
- Settings (map, max cars, name) are environment variables in `compose.yaml`.
