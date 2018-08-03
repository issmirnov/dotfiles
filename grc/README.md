# grc config

We are using https://github.com/garabik/grc to colorize output.

## Information

- `grc` and `grcat` are python scripts that live in` ~/.dotfiles/bin`. When invoked,
  they search for ~/.grc which is symlinked to this folder. The file `grc.conf` defines
  regex mappings of command keywordst to config files
- Inside of ~/.dotfiles/zsh/config/grc.sh, we have a ZLE `accept-line` injector that will
  append `| grcat conf.$prog` for any program configs in this folder. Set $DISABLE_GRC to
  disable.


## Usage

- `grc ping google.com`
- `ping google.com | grcat conf.ping`
