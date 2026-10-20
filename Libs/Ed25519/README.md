# Ed25519 for QuestTogether

Small Lua 5.1/5.2 adaptation of the signing and SHA-512 portions of
[public-domain TweetNaCl, 20140427](https://tweetnacl.cr.yp.to/20140427/tweetnacl.c).
Original authors: Daniel J. Bernstein, Tanja Lange, Peter Schwabe.
The upstream project explicitly places its code in the public domain.

The addon pins separate developer and VIP issuer public keys. A VIP peer key is
accepted only after its certificate verifies against the pinned VIP issuer.
That identity grants cosmetics only, never developer authority. The port
checks canonical signatures and public-key encodings. It has regression and
OpenSSL interoperability coverage, but has not had an independent cryptographic
audit. Lua execution is not guaranteed constant time.

The developer signing seed stays in the private QuestTogetherDev companion.
The VIP issuer seed stays in the private reward service. Each VIP installation
receives its own signing seed in a private activation; it is stored separately
from profiles and diagnostic snapshots. Never ship any of those private keys.
Requests bind their sender, purpose, identity and timestamp. VIP proofs also bind
the sender's current communication session and cosmetic visibility.

Signing, public-key derivation and verification accept arithmetic checkpoints.
VIP operations yield at those checkpoints and progress through the shared runtime
coordinator, with bounded queues and per-frame work. Interoperability tests use
fresh test-only issuer keys and compare against OpenSSL and Python cryptography.
