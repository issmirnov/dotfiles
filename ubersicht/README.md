# Übersicht config

## Installation

See https://github.com/felixhageloh/uebersicht

```
brew cask install ubersicht
open /Applications/Übersicht.app
```

## Details

This folder is linked to "~/Library/Application Support/Übersicht/widgets".
Übersicht will automatically live reload any changes.

## Troubleshooting

If the widgets don't appear, check http://localhost:41416/ for the status of the server.

## Commands

```applescript
tell application "Übersicht" to reload
tell application "Übersicht" to refresh
```
