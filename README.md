# roblox-game

Roblox Studio project kept in GitHub using [Rojo](https://rojo.space).

## Layout
| Folder | Ends up in Studio as |
|---|---|
| `src/server` | `ServerScriptService.Server` |
| `src/client` | `StarterPlayer.StarterPlayerScripts.Client` |
| `src/shared` | `ReplicatedStorage.Shared` |

## Working on it
1. Install [Rokit](https://github.com/rojo-rbx/rokit), then run `rokit install` in this folder (installs Rojo).
2. Install the Rojo plugin in Studio (`rojo plugin install`).
3. Run `rojo serve`, then press **Connect** in the Rojo plugin in Studio.
4. Edit files here: changes sync into Studio live. Commit and push with git as normal.

## Tablet (press M)
| Folder | Ends up in Studio as |
|---|---|
| `src/tablet` | `ReplicatedStorage.TabletShared` (ChessRules, PieceArt, ShopItems, TabletView) |
| `src/tools/DeepwokenTablet/Hold.server.luau` | script inside `StarterPack.Deepwoken Tablet` (the tool itself, with its meshes, lives in the place file) |

Chess rules are verified with perft (`ChessRules.perft`) against standard test positions.
To add shop items, edit `src/tablet/ShopItems.luau`.
