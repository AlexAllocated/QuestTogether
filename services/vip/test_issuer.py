import asyncio
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import AsyncMock, patch

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from issuer import Issuer, ClaimError

OWNER, PLAYER, OTHER = "111111111111111111", "222222222222222222", "333333333333333333"
CLAIM = "QTCLAIM1." + "a" * 32


class IssuerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "state"
        self.issuer = Issuer(self.path, OWNER, initialize=True)

    def tearDown(self):
        self.issuer.close()
        self.tmp.cleanup()

    def test_owner_auth_and_no_grant_on_unapproved_claim(self):
        with self.assertRaises(ClaimError):
            self.issuer.grant(OTHER, PLAYER)
        with self.assertRaises(ClaimError):
            self.issuer.claim(PLAYER, CLAIM)
        self.assertIsNone(self.issuer.status(PLAYER))

    def test_permanent_idempotent_grant_retrieval_and_separate_installations(self):
        self.issuer.grant(OWNER, PLAYER, "Community contribution")
        original = self.issuer.claim(PLAYER, CLAIM)
        self.issuer.grant(OWNER, PLAYER, "Duplicate approval")
        self.assertEqual(original, self.issuer.claim(PLAYER, CLAIM))
        second = self.issuer.claim(PLAYER, "QTCLAIM1." + "b" * 32)
        self.assertNotEqual(original, second)
        self.assertEqual(original.split(".")[4], second.split(".")[4])  # same permanent grant
        self.assertEqual(self.issuer.status(PLAYER)["installations"], 2)
        with self.assertRaises(ClaimError):
            self.issuer.claim(OTHER, CLAIM)
        public = self.issuer.public_hex
        self.issuer.close()
        self.issuer = Issuer(self.path, OWNER)
        self.assertEqual(public, self.issuer.public_hex)
        self.assertEqual(original, self.issuer.claim(PLAYER, CLAIM))

    def test_signature_and_private_identity_match_without_discord_id_in_certificate(self):
        self.issuer.grant(OWNER, PLAYER)
        prefix, claim, seed, version, grant, public, signature = self.issuer.claim(PLAYER, CLAIM).split(".")
        self.assertEqual(prefix, "QTVIPKEY1")
        self.assertEqual(version, "QTVIP1")
        key = Ed25519PrivateKey.from_private_bytes(bytes.fromhex(seed))
        self.assertEqual(key.public_key().public_bytes_raw().hex(), public)
        message = f"QTVIP1\n{grant}\n{public}".encode()
        self.issuer.key.public_key().verify(bytes.fromhex(signature), message)
        with self.assertRaises(InvalidSignature):
            self.issuer.key.public_key().verify(bytes.fromhex(signature), message + b"x")
        self.assertNotIn(PLAYER, ".".join((version, grant, public, signature)))
        self.assertEqual((self.path / "issuer.key").stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.path / "grants.sqlite3").stat().st_mode & 0o777, 0o600)

    def test_bad_claims_and_capacity_do_not_corrupt_entitlement(self):
        self.issuer.grant(OWNER, PLAYER)
        for code in ("", CLAIM + "\n", "QTVIPKEY1." + "x" * 500, CLAIM.upper(), "x" * 10000):
            with self.assertRaises(ClaimError):
                self.issuer.claim(PLAYER, code)
        first = None
        for n in range(10):
            code = f"QTCLAIM1.{n:032x}"
            activation = self.issuer.claim(PLAYER, code)
            if n == 0:
                first = activation
        with self.assertRaises(ClaimError):
            self.issuer.claim(PLAYER, CLAIM)
        self.assertEqual(first, self.issuer.claim(PLAYER, "QTCLAIM1." + "0" * 32))
        self.assertIsNotNone(self.issuer.status(PLAYER))

    def test_missing_issuer_is_not_silently_rotated(self):
        with self.assertRaises(RuntimeError):
            Issuer(self.path / "missing", OWNER)


class BotTests(unittest.IsolatedAsyncioTestCase):
    async def test_private_claims_owner_checks_and_scoped_registration(self):
        from bot import RewardBot
        with tempfile.TemporaryDirectory() as temp:
            issuer = Issuer(temp, OWNER, initialize=True)
            issuer.grant(OWNER, PLAYER)
            issuer.close()
            with patch.dict(os.environ, {"QT_VIP_DATA": temp, "QT_VIP_OWNER_ID": OWNER,
                                        "QT_VIP_GUILD_ID": "444444444444444444", "QT_VIP_REGISTER_COMMAND": "1"}):
                bot = RewardBot()
                bot.http.upsert_guild_command = AsyncMock()
                await bot.setup_hook()
                args = bot.http.upsert_guild_command.call_args
                self.assertEqual(args.args[1], 444444444444444444)
                self.assertEqual(args.kwargs["payload"]["name"], "qt")
                interaction = AsyncMock()
                interaction.guild_id = 444444444444444444
                interaction.user.id = int(PLAYER)
                interaction.response.is_done = lambda: False
                await bot.claim(interaction, CLAIM)
                self.assertTrue(interaction.followup.send.call_args.kwargs["ephemeral"])
                self.assertIn("QTVIPKEY1.", interaction.followup.send.call_args.args[0])
                user = "<@" + OTHER + ">"
                await bot.grant(interaction, user)
                self.assertIsNone(bot.issuer.status(OTHER))
                await bot.issue(interaction, user, CLAIM)
                self.assertNotIn("QTVIPKEY1.", interaction.followup.send.call_args.args[0])
                interaction.user.id = int(OWNER)
                await bot.grant(interaction, OTHER)  # Friend outside the guild: no member lookup.
                await bot.issue(interaction, OTHER, CLAIM)
                self.assertIn("QTVIPKEY1.", interaction.followup.send.call_args.args[0])
                interaction.guild_id = 1
                await bot.claim(interaction, CLAIM)
                self.assertIn("QuestTogether server", interaction.response.send_message.call_args.args[0])
                await bot.close()


if __name__ == "__main__":
    unittest.main()
