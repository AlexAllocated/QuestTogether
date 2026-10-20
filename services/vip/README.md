# QuestTogether VIP service

VIP is a permanent cosmetic entitlement owned by a numeric Discord user ID.
The issuer records approvals in SQLite. Each client claim gets a separate
OS-generated Ed25519 identity and a permanently signed certificate; alts use
the account-wide `QuestTogetherVIP` SavedVariables root. No character name,
BattleTag or Discord ID is included in public certificates.

Players can DM **@chevcast** after joining the QT server, or send a friend request
first. Screenshot/contribution review stays a direct conversation. There is no
automated judgment about whether a contribution qualifies.

## Commands

- `/qt grant user reason`: owner only; permanent approval, idempotent.
- `/qt claim code`: approved users claim/retrieve their own activation.
- `/qt issue user code`: owner only; generate an approved player's activation
  to forward privately (including players who contacted the owner as friends).
- `/qt status`: privately check your own entitlement.

The `user` argument accepts a mention or numeric Discord user ID, so the owner
can grant and issue for a friend who is not a member of the QT server.

Every response is ephemeral. Activation codes contain a private signing seed:
never put them in public messages, tickets, logs, or screenshots. The bot never
sends unsolicited DMs. Grant authorization uses `QT_VIP_OWNER_ID`, not username,
roles, channel permissions, or administrator status.

## Setup

Use Python 3.11+ and install `requirements.txt` into a private virtual environment.
Run once to provision a **dedicated** issuer key:

```sh
python services/vip/issuer.py init --data /private/qt-vip \
  --owner-id DISCORD_USER_ID --lua-output VIPPublicKey.lua
```

Review the public key change before releasing QT. Do not regenerate or replace
the issuer key after release: existing certificates depend on it. The service
refuses to create a new key implicitly at startup.

Environment:

- `DISCORD_BOT_TOKEN`: existing bot token with access to the QT server.
- `QT_VIP_DATA`: private absolute directory containing the key and SQLite ledger.
- `QT_VIP_OWNER_ID`: verified numeric Discord user ID for chevcast.
- `QT_VIP_GUILD_ID`: QT server ID.
- `QT_VIP_REGISTER_COMMAND=1`: register/update the guild's `/qt` command at startup.
  The worker upserts only that command, never bulk-syncs/removes other commands.
  Check for an existing unrelated `/qt` before enabling registration.

Run `python services/vip/bot.py`. The worker uses no privileged Discord intents,
does not read message content, and can share the existing bot application with
an unrelated message/voice worker that does not process this command.

For this workstation, install the provided user service after replacing
`@REPOSITORY@` with the absolute checkout path. Its private environment file lives
at `.local/vip-service/service.env` (mode 0600); state lives at
`.local/vip-service/data` (0700). Then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now questtogether-vip.service
systemctl --user status questtogether-vip.service
```

The PC must be on and connected to Discord. WoW and the editor may be closed.
The service restarts after failures and starts with the user's session. For a
future always-on host, move the entire private data directory and environment;
preserve the existing issuer key and public pin.

Back up the **entire private data directory** with the service stopped (or use
SQLite's backup API). Protect backups as credentials. Repeated claims retrieve
the original activation, and ten new installations per user per day bounds
abuse without expiring the grant. Removing someone from Discord does not revoke
their installed cosmetic. There is no revocation promise for permanent offline
certificates.

## In-game verification and limits

The pinned reward public key verifies the certificate before its certified key
may verify a sender/session/time-bound proof. This grants **cosmetics only**.
Developer signatures, diagnostic opt-in, location sharing and ignore rules stay
separate. Existing glows and class colors remain meaningful; developer artwork
takes precedence when both apply.

VIP proofs use the ordinary protocol catalog, scheduler and bounded transfer
service. Publication is every 120 seconds; remote proof lifetime is 300 seconds.
Fresh installs/late joiners may wait for the next publication. Disabled cosmetics
publish a signed withdrawal; rapid changes coalesce outside the receiver's
verification cooldown. Queue failures retry after five seconds, while ambiguous
native submissions wait for the ordinary next publication. Verification and signing advance incrementally from
RuntimeCoordinator; peer caches and pending work are bounded and retired on
session changes, ignores, departure and disable.

Certificates alone are public and insufficient to impersonate a VIP. Someone
deliberately sharing their private activation/SavedVariables can share the
cosmetic; this is not DRM or an account-ownership proof. Gameplay functionality
does not require VIP.

## Checks

```sh
python -m unittest discover -s services/vip -p 'test_*.py'
```

Use `QT_TEST_LUA=/path/to/lua` for the optional issuer-to-addon interoperability
check. No test reads production keys, grants rewards to real users or contacts
Discord. The live release gate is activation and remote rendering in Forever and
Retail; offline tests do not prove client taint, appearance or actual delivery.

Before release, have an approved player claim and activate on each supported
client, then check their star, individual tooltip, roster/cluster rows and chat
prefix from a second updated client. Confirm the visibility checkbox, reload,
alt login and profile reset; keep private activation codes out of screenshots.
Check `/qt grant` and `/qt issue` from the owner's phone and `/qt claim` from an
approved user's account. Service startup/command registration alone does not
establish those live interaction results.
