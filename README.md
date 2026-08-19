# minios-live-config

MiniOS system-configuration components derived from Debian `live-config`.
Components run during late userspace on live boots and support systemd and
sysvinit backends.

## Configuration

`boot=live` activates live-config. Components are selected with
`live-config.components` or excluded with `live-config.nocomponents`.
Configuration can come from:

- kernel parameters;
- `/etc/live/config.conf` and `/etc/live/config.conf.d/*.conf`;
- `minios/config.conf` and `minios/config.conf.d/*.conf` on the live medium.

Kernel parameters take precedence. Media configuration takes precedence over
root-filesystem configuration. Persistent systems normally run each component
once and record state under `/var/lib/live/config/`.

## MiniOS Features

- User, root, hostname, locale, timezone, keyboard, autologin, service, module,
  hook, and boot-log configuration
- Wired IPv4 policy through NetworkManager or ifupdown
- User-directory linking or bind mounting on the existing writable MiniOS data
  medium
- Sudo, PolicyKit, OpenSSH, XRDP, X11, password-hint, and screen-lock posture
  controls
- Systemd and sysvinit startup integration
- Machine-readable capability inventory at
  `/usr/share/minios/capabilities/minios-live-config.json`

`LIVE_SECURITY_PROFILE` is not a runtime option. Applications may offer
profiles, but they must save the concrete settings enforced by this package.

## Network

`LIVE_NETWORK_METHOD` accepts `dhcp`, `static`, or `off`. Unset and `dhcp`
preserve the image's existing network setup. Static and off modes select a wired
interface explicitly or require exactly one eligible wired interface.
`LIVE_NETWORK_BACKEND=auto` prefers NetworkManager and falls back to ifupdown.
Successful one-time application is stamped at `/var/lib/live/config/network`.

## User Media

`LIVE_LINK_USER_DIRS` and `LIVE_BIND_USER_DIRS` are mutually exclusive. The
default media-relative path is `/minios/userdata`. The component uses the
existing `/run/initramfs/memory/data` mount and accepts only writable local
block-backed FAT32, exFAT, or NTFS media. RAM, optical, network, overlay,
read-only, unsupported filesystems, and all `toram` forms are rejected.

Managed directories are Desktop, Documents, Downloads, Music, Pictures, Public,
Templates, and Videos. Paths and contents are validated; two populated trees
are never merged automatically. Disabling the feature copies data back before
removing managed links or mounts.

## Module User Groups

Modules that require supplementary groups for the live user can install
`*.groups` files under `/usr/share/live/config/user-default-groups.d/`. Group
names may be separated by whitespace; blank lines and `#` comments are ignored.
The `user-groups` component adds existing declared groups to the live user
after user creation. It runs idempotently on each live-config invocation so a
module added to an existing persistent session can grant its required groups.

## Security

Unset posture settings preserve historical MiniOS behavior. Explicit settings
are applied only when their component or package is present. `noroot` takes
precedence over sudo and PolicyKit convenience settings. PolicyKit `disabled`
removes the MiniOS passwordless rule; it is not a deny-all policy.

See `live-config(7)` for all boot parameters and variables and
`capabilities/README.md` for the capability schema.

## Development

```bash
make test
make install DESTDIR=/tmp/minios-live-config
make -C manpages build
```

## License

GPL-3.0+
