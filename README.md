# Omarchy Cheatsheets

One hotkey, every cheatsheet. Searchable hotkey and command references for the
tools you actually use — tmux, Docker, Neovim, Unity, git, lazygit, kubectl,
SSH — plus your own live Omarchy keybindings, in a themed fullscreen overlay.

The point is that **the sheets are data, not code**: drop a JSON file into
`~/.config/omarchy/cheatsheets/` and a new tab appears. No rebuild, no QML.

## Install

```bash
omarchy plugin add https://github.com/YOU/omarchy-cheatsheets
omarchy bar put abelk.cheatsheets --section right
omarchy restart shell
```

Then bind a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + K", "Cheatsheets", "omarchy-shell shell toggle abelk.cheatsheets")
```

Install with `bar put` rather than `--enable`: passing `--enable` first registers
the plugin on its own, and `bar put` then reports success while leaving it off
the bar.

## Keys

| Key | Action |
| --- | --- |
| *any letter* | type straight into the search — no `/` needed |
| `Tab` / `Shift+Tab`, `←` `→` | previous / next sheet |
| `↑` `↓`, `Ctrl+P` / `Ctrl+N` | move the selection |
| `PgUp` `PgDn`, `Ctrl+U` / `Ctrl+D` | page up / down |
| `Home` `End` | first / last entry |
| `Enter` | copy the key chord to the clipboard |
| `Ctrl+R` | reload the sheets from disk |
| `Esc` | clear the search, then close |

Search matches words in any order, as substrings or fuzzily — "next tab", "tab
next" and "nxt tb" all find *Next tab*. A hit in the key chord ranks above a hit
in the description.

While you are searching, results come from **every** sheet, grouped by tool with
the current one first. That is the point: you often don't know which tool the
thing you half-remember belongs to.

## Bundled sheets

| Sheet | Shown when | Source |
| --- | --- | --- |
| tmux | `tmux` installed | Written against Omarchy's `~/.config/tmux/tmux.conf` — prefix is `Ctrl+Space` |
| Docker | `docker` | Hand-maintained |
| Compose | `docker` | Hand-maintained |
| Neovim | `nvim` | Vim motions + LazyVim defaults |
| Unity | `unityhub` or `unity-editor` | Unity Editor defaults, hand-maintained |
| Git | `git` | Hand-maintained |
| Lazygit | `lazygit` | Hand-maintained |
| kubectl | `kubectl` | Hand-maintained |
| SSH | `ssh` | Hand-maintained |
| Omarchy | `hyprctl` | **Generated live** from `omarchy-menu-keybindings --print` |

A sheet only appears if one of its `detect` binaries is on your `PATH`, so the
tab strip stays as short as your toolchain is.

The Omarchy sheet is read from your running config every time the overlay opens,
so it can't drift. (It goes through `omarchy-menu-keybindings --print` rather
than `hyprctl binds -j` because Hyprland reports Lua binds without their key —
59 of 225 on a stock install — and that command already carries the Lua
evaluation and xkb keycode resolution needed to put them back.)

## Adding your own

Drop a JSON file in `~/.config/omarchy/cheatsheets/`:

```json
{
  "id": "httpie",
  "name": "HTTPie",
  "icon": "󰖟",
  "order": 45,
  "detect": ["http"],
  "windowClasses": [],
  "note": "Optional line shown in the footer.",
  "sections": [
    {
      "title": "Requests",
      "entries": [
        { "keys": "http GET example.com", "desc": "Plain GET" },
        { "keys": "http -f POST url a=1", "desc": "Form-encoded POST" }
      ]
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `id` | Unique. Reuse a bundled id (`tmux`, `docker`, …) to **replace** that sheet entirely. |
| `name` | Tab label. |
| `icon` | Optional glyph shown before the name. |
| `order` | Tab position. Sheets without one sort to the end, alphabetically. |
| `detect` | Binaries; the sheet hides if none are on `PATH`. Omit to always show. |
| `windowClasses` | Optional. If the focused window matches one, that tab is preselected when the overlay opens. |
| `note` | Optional footer line. |

`Ctrl+R` inside the overlay reloads without restarting the shell.

To check a sheet before relying on it:

```bash
~/.config/omarchy/plugins/abelk.cheatsheets/bin/cheatsheets-load | jq -r '.[].id'
```

Add `--all` to include sheets whose tool isn't installed — useful when you're
writing one for a machine you're not currently on.

## How it works

- `bin/cheatsheets-load` does all the disk I/O: globs `data/*.json` and the user
  directory, drops undetected tools, runs generators, merges by id, and prints
  one JSON array. QML's `FileView` reads a single path and can't glob a
  directory, so doing this in one shell call is both simpler and one process
  instead of N.
- `Cheatsheets.qml` is the overlay — a layer-shell surface modelled on the
  built-in emoji picker, using the `[menu]` theme tokens so it follows whatever
  theme you're on.
- `Search.js` builds a flat row model (headers and entries in one list), which is
  what makes "move to the next entry, skipping headers" and stable scroll
  positions straightforward.
- `BarWidget.qml` is the bar icon. It toggles over IPC rather than owning a
  panel, because a plugin declaring both `overlay` and `bar-widget` is owned by
  the shell's panel loader.

Generators are only ever resolved inside the plugin's own `bin/` directory — a
sheet in your config directory naming one gets its static sections instead.

## Remove

```bash
omarchy plugin remove abelk.cheatsheets
```

Nothing is written outside the plugin directory; your own sheets in
`~/.config/omarchy/cheatsheets/` are left alone.

## License

MIT
