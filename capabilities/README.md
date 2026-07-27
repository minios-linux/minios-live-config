# minios-live-config capabilities

Machine-readable inventory of **public** live-config features shipped by this package.

Installed path:

```text
/usr/share/minios/capabilities/minios-live-config.json
```

Schema version: 1.

## Rules

1. Describe the **full supported public surface**, not only knobs used by one consumer (e.g. security profiles).
2. List only what components **actually enforce** today.
3. When adding a new conf key or cmdline option, update this JSON in the same change.
4. Append capability ids for new public behavior; do not repurpose existing ids.
5. `default` describes effective historical behavior. An unset value may still
   mean that the component leaves existing package configuration unchanged.

## Validation

```bash
./scripts/validate-capabilities
# or
make test
```

## Capability families

The schema covers component selection, identity and accounts, localization,
keyboard, autologin, services, network, user media, security posture, module
mode, hooks, debugging, and log export. Consumers must inspect individual
entries rather than infer support from the package version.

## Wired network

| Config key | Values | Behavior |
|------------|--------|----------|
| `LIVE_NETWORK_METHOD` | `dhcp`, `static`, `off` | Unset and DHCP preserve image defaults; static writes an IPv4 profile; off disables automatic IPv4. |
| `LIVE_NETWORK_INTERFACE` | interface name | Required unless exactly one wired non-loopback interface is available. |
| `LIVE_NETWORK_ADDRESS` | IPv4 address | Required for static mode. |
| `LIVE_NETWORK_PREFIX` | `0`-`32` | Static prefix, default `24`. |
| `LIVE_NETWORK_GATEWAY` | IPv4 address | Optional gateway. |
| `LIVE_NETWORK_DNS` | comma-separated addresses | Optional IPv4 or IPv6 DNS servers. |
| `LIVE_NETWORK_BACKEND` | `auto`, `nm`, `ifupdown` | Auto prefers NetworkManager. |

Wireless interfaces are excluded. Invalid settings are rejected without
stamping success. Successful application records `/var/lib/live/config/network`.

## User media

`LIVE_LINK_USER_DIRS` and `LIVE_BIND_USER_DIRS` are mutually exclusive.
`LIVE_USER_DIRS_PATH` is a safe media-relative path, defaulting to
`/minios/userdata`. The component requires the existing writable local MiniOS
data mount on FAT32, exFAT, or NTFS and rejects network, optical, RAM, overlay,
read-only, unsupported, and `toram` storage. It does not merge two populated
directory trees.

## Security posture knobs

The registry now advertises the first security-profile posture knobs that are enforced by components:

| Capability id | Config key | Values | What it does |
|---------------|------------|--------|--------------|
| `live-config.sudo.mode` | `LIVE_SUDO_MODE` | `passwordless`, `password`, `disabled` | Controls the live user's sudo rule. Unset means the historical MiniOS default, `passwordless`. |
| `live-config.polkit.mode` | `LIVE_POLKIT_MODE` | `passwordless`, `password`, `disabled` | Controls the MiniOS passwordless PolicyKit convenience rule. Unset means the historical MiniOS default, `passwordless`. |
| `live-config.ssh.permit-root-login` | `LIVE_SSH_PERMIT_ROOT_LOGIN` | `true`, `false` | When explicitly set and OpenSSH is installed, writes root-login policy. |
| `live-config.ssh.password-authentication` | `LIVE_SSH_PASSWORD_AUTHENTICATION` | `true`, `false` | When explicitly set and OpenSSH is installed, writes password-authentication policy. |
| `live-config.xrdp.mode` | `LIVE_XRDP_MODE` | `relaxed`, `hardened`, `disabled` | Controls XRDP listener/security/root-login posture. |
| `live-config.x11.mode` | `LIVE_X11_MODE` | `relaxed`, `hardened` | Controls MiniOS X11 `-ac` and wrapper posture. |
| `live-config.issue.password-hints` | `LIVE_ISSUE_PASSWORD_HINTS` | `true`, `false` | Shows or hides default password hints in `/etc/issue`. |
| `live-config.lockscreen.mode` | `LIVE_LOCKSCREEN_MODE` | `relaxed`, `hardened` | Keeps historical relaxed lock behavior or preserves/enables locking where supported. |

Behavior notes:

1. `passwordless` preserves old MiniOS behavior.
2. `password` keeps administrative access but requires normal authentication.
3. `disabled` removes the MiniOS convenience grant. For sudo, user creation also removes the live user from the `sudo` group. For PolicyKit, this is not a deny-all rule; it removes the passwordless grant and lets the distribution's normal PolicyKit rules decide.
4. Legacy `noroot` still takes precedence and disables root/admin setup more broadly.
5. XRDP, X11, OpenSSH, and lockscreen settings are effective only when the
   corresponding packages or configuration files are present.
6. `LIVE_SECURITY_PROFILE` is intentionally absent. Profiles are consumer-side
   presets expanded into concrete capability keys.
