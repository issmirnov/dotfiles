# MacOS Launch Agents

Destination: `~/Library/LaunchAgents/`

## Remote Clipboard Managers

`pbcopy.plist` sets up a listener on localhost 2224.
Combined with an SSH directive `RemoteForward 2224 127.0.0.1:2224`,
this allows us to use `nc -q1 localhost 2224` on remote machines
to write to the MacOS clipboard.

See the tmux config setting `override_copy_command` for an example.

Note that you will need to launch this service with `launchctl load ~/Library/LaunchAgents/pbcopy.plist` first.

