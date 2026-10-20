"""Private VIP entitlement ledger and Ed25519 issuer. Never package its data."""
import argparse
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey


class ClaimError(ValueError):
    pass


def discord_id(value):
    value = str(value)
    if not re.fullmatch(r"[1-9][0-9]{5,19}", value):
        raise ClaimError("Invalid Discord user ID.")
    return value


class Issuer:
    def __init__(self, directory, owner_id, *, initialize=False):
        self.owner = discord_id(owner_id)
        self.directory = Path(directory)
        self.directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.directory.chmod(0o700)
        key_path = self.directory / "issuer.key"
        if not key_path.exists():
            if not initialize:
                raise RuntimeError("Issuer key missing. Restore it from backup; do not rotate it implicitly.")
            key = Ed25519PrivateKey.generate().private_bytes_raw()
            fd = os.open(key_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "wb") as handle:
                handle.write(key)
        key_path.chmod(0o600)
        self.key = Ed25519PrivateKey.from_private_bytes(key_path.read_bytes())
        db_path = self.directory / "grants.sqlite3"
        fd = os.open(db_path, os.O_WRONLY | os.O_CREAT, 0o600)
        os.close(fd)
        db_path.chmod(0o600)
        self.db = sqlite3.connect(db_path)
        self.db.execute("PRAGMA foreign_keys = ON")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS grants (
                user_id TEXT PRIMARY KEY, grant_id TEXT UNIQUE NOT NULL,
                granted_at INTEGER NOT NULL, granted_by TEXT NOT NULL, reason TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS activations (
                user_id TEXT NOT NULL REFERENCES grants(user_id),
                claim TEXT NOT NULL, seed BLOB NOT NULL, certificate TEXT NOT NULL,
                created_at INTEGER NOT NULL, PRIMARY KEY(user_id, claim)
            );
        """)
        self.db.commit()

    @property
    def public_hex(self):
        return self.key.public_key().public_bytes_raw().hex()

    def grant(self, actor, recipient, reason=""):
        if discord_id(actor) != self.owner:
            raise ClaimError("Only @chevcast can grant VIP.")
        recipient = discord_id(recipient)
        reason = reason.strip()
        if len(reason) > 300:
            raise ClaimError("Keep the private grant reason under 300 characters.")
        with self.db:
            self.db.execute(
                "INSERT OR IGNORE INTO grants VALUES (?, ?, ?, ?, ?)",
                (recipient, secrets.token_hex(16), int(time.time()), self.owner, reason),
            )
        return self.status(recipient)

    def status(self, recipient):
        user = discord_id(recipient)
        row = self.db.execute("SELECT granted_at FROM grants WHERE user_id = ?", (user,)).fetchone()
        if not row:
            return None
        count = self.db.execute("SELECT COUNT(*) FROM activations WHERE user_id = ?", (user,)).fetchone()[0]
        return {"granted_at": row[0], "installations": count}

    def claim(self, recipient, code):
        user = discord_id(recipient)
        if not isinstance(code, str) or not re.fullmatch(r"QTCLAIM1\.[0-9a-f]{32}", code):
            raise ClaimError("Paste the claim code from QT's How to become a VIP window.")
        grant = self.db.execute("SELECT grant_id FROM grants WHERE user_id = ?", (user,)).fetchone()
        if not grant:
            raise ClaimError("VIP has not been granted yet. DM @chevcast after joining the QT server or becoming friends.")
        with self.db:
            self.db.execute("BEGIN IMMEDIATE")
            row = self.db.execute(
                "SELECT seed, certificate FROM activations WHERE user_id = ? AND claim = ?", (user, code)
            ).fetchone()
            if row is None:
                # Bound unattended issuance, without expiring the entitlement or
                # charging returning users for retrieving an existing activation.
                recent = self.db.execute(
                    "SELECT COUNT(*) FROM activations WHERE user_id = ? AND created_at > ?",
                    (user, int(time.time()) - 86400),
                ).fetchone()[0]
                if recent >= 10:
                    raise ClaimError("Ten new installations were claimed today. Try again tomorrow or contact @chevcast.")
                identity = Ed25519PrivateKey.generate()
                seed = identity.private_bytes_raw()
                public = identity.public_key().public_bytes_raw().hex()
                message = f"QTVIP1\n{grant[0]}\n{public}".encode("ascii")
                certificate = f"QTVIP1.{grant[0]}.{public}.{self.key.sign(message).hex()}"
                self.db.execute(
                    "INSERT INTO activations VALUES (?, ?, ?, ?, ?)",
                    (user, code, seed, certificate, int(time.time())),
                )
                row = seed, certificate
        return f"QTVIPKEY1.{code.split('.')[1]}.{row[0].hex()}.{row[1]}"

    def close(self):
        self.db.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("init", "public-key"))
    parser.add_argument("--data", type=Path, required=True)
    parser.add_argument("--owner-id", required=True)
    parser.add_argument("--lua-output", type=Path)
    args = parser.parse_args()
    issuer = Issuer(args.data, args.owner_id, initialize=args.command == "init")
    if args.lua_output:
        args.lua_output.write_text(
            "-- Public reward issuer key only. Private key stays in the VIP service data directory.\n"
            f'_G.QuestTogether.vipIssuerPublicKeyHex = "{issuer.public_hex}"\n'
        )
    else:
        print(issuer.public_hex)  # Public key only, never private activation material.
    issuer.close()


if __name__ == "__main__":
    main()
