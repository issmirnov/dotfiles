# Ivan's Dotfiles

>  Your dotfiles will most likely be the longest project you ever work on.

Quote by Anish Athalye on his
[blog](http://www.anishathalye.com/2014/08/03/managing-your-dotfiles/).

I completely agree with Anish, and thus maintain this repo for my dotfiles.
There are many like them, but these are mine.

## Prerequisites

You will need to have the following installed:

- python: for dotbot
- vim: for vimrc
- zsh: for the shell

## Installation

Clone and run `./install`. This will download
[dotbot](https://github.com/anishathalye/dotbot) and symlink everything into
place. If you don't have ZSH already as your default shell, run
`~/.dotfiles/zsh/setup`

If you would like to only install the ZSH component and nothing else, use
`minstall`. This references `minimal.comf.yaml` and links the `zshrc` and git
hooks only.

If you trust me, you can also do `wget https://smirnov.link/d -O - | sh`. This
pulls the `d` file which clones the repo, runs a full install and tells you how
to install zsh.

### Ansible

There's an [ansible role](https://galaxy.ansible.com/issmirnov/dotfiles/) for this repo. Simply add `issmirnov.dotfiles` as a role.

## Submodules Used

- [Dotbot](https://github.com/anishathalye/dotbot) for installation.
- [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh) for zsh foundation.
- [Vundle](https://github.com/VundleVim/Vundle.vim) for vim.

## Points of Interest

- The post commit hook in the [git](git/) directory is very interesting. It
  checks for changes, and depending on which rules are matched will run certain
  commands. Ie, if the zsh folder contains changes we will source zshrc for
  you. With changes to vim we will rerun the vim install script.
- The [i3](i3/) folder contains my solution for managing i3 config across
  multiple machines. My fleet ranges from weak laptops to triple head power
  beasts, and it's annoying to copy paste config. There's more detail in the
  folder. Basically you can add rules for a specific host and factor out common
  config, which gets spliced in dynamically on every pull.
- The [vim](vim/) directory is relatively standalone, and contains my attempt
  at building a sane vim config that isn't complex enough to launch nukes when
  your cat sneezes on the keyboard.

## Macos Window manager stack

I've been getting a lot of questions about my MacOS window management. Here's the full stack:

- https://github.com/koekeishiya/yabai is used to tile my windows.
  - the `yabai` folder has general config - setting border colors, focus rules, etc.
  - NOTE: The top two lines are for SIP patched machines. See the inline comment.
- https://github.com/koekeishiya/skhd is a hoteky daeemon, used to interact with yabai.
  - Config folder `skhd` - note the dynamic generator. You can just copy `base` to your `.skhd`
  - This is where all the shortcuts are set up. See the inline comments for examples
  - NOTE: A lot of the shortcuts require extensive finger yoga on traditiona keyboards.
    I use a custom mechanical keyboard running QMK (https://github.com/issmirnov/qmk-keebs)
    with home row mods (https://precondition.github.io/home-row-mods), so I have a dedicated
    "Navigation" layer that has single button combos for all the crazy shortcuts.
- https://tracesof.net/uebersicht/
  - Config folder `ubersicht`
  - This sets up a custom status bar with useful indicators (https://ivans.io/better-status-bar-for-macos/)
- https://contexts.co/ - fast window switcher, activated with Ctrl+Space. I disabled the sidebar and only use the switcher.
- https://www.alfredapp.com/ - drop in replacement for spotlight. I generally only use it to lock
  my screen or open apps. If you want to go deeper, check out: https://wiki.nikitavoloboev.xyz/macos/macos-apps/alfred

## A Note about the License & Copyright:

Unless attributed otherwise, everything is under the MIT license (see LICENSE
for more info).

Some stuff is not from me, and without attribution, and I no longer remember
where I got it from. I apologize for that.

Feel free to copy whatever suits you, and open an issue with a question if you
need some help.
