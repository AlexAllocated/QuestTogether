"""QT-only Discord reward worker; no message-content intent or guild-wide reads."""
import asyncio
import logging
import os

import discord
from discord import app_commands

from issuer import ClaimError, Issuer, discord_id


def recipient_id(value):
    # A string option also works for friends who are not in the QT guild.
    return discord_id(value.strip().removeprefix("<@").removeprefix("!").removesuffix(">"))


class RewardBot(discord.Client):
    def __init__(self):
        super().__init__(intents=discord.Intents.none(), allowed_mentions=discord.AllowedMentions.none())
        self.issuer = Issuer(os.environ["QT_VIP_DATA"], os.environ["QT_VIP_OWNER_ID"])
        self.guild_id = int(os.environ["QT_VIP_GUILD_ID"])
        self.tree = app_commands.CommandTree(self)
        self.group = app_commands.Group(name="qt", description="QuestTogether VIP rewards")
        self.group.add_command(app_commands.Command(name="grant", description="Grant permanent VIP (chevcast only)", callback=self.grant))
        self.group.add_command(app_commands.Command(name="claim", description="Activate VIP on a WoW installation", callback=self.claim))
        self.group.add_command(app_commands.Command(name="status", description="Check your VIP reward", callback=self.status))
        self.group.add_command(app_commands.Command(name="issue", description="Issue an activation for a player (chevcast only)", callback=self.issue))
        self.tree.add_command(self.group, guild=discord.Object(id=self.guild_id))
        self.tree.on_error = self.command_error

    async def setup_hook(self):
        # Upsert just /qt. CommandTree.sync() would delete unrelated guild
        # commands on a shared application. Never mutate global commands here.
        if os.environ.get("QT_VIP_REGISTER_COMMAND") == "1":
            await self.http.upsert_guild_command(
                self.application_id, self.guild_id, payload=self.group.to_dict(self.tree)
            )

    async def on_ready(self):
        logging.warning("QuestTogether VIP worker connected")

    async def checked(self, interaction, action):
        if interaction.guild_id != self.guild_id:
            await interaction.response.send_message("Use this command in the QuestTogether server.", ephemeral=True)
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            message = action()
        except ClaimError as error:
            message = str(error)
        except Exception:
            # Do not log command bodies, activation codes, interaction tokens,
            # signing seeds, or exception reprs. Operators can inspect health.
            logging.error("VIP command failed")
            message = "VIP service unavailable. Please try again later."
        await interaction.followup.send(message, ephemeral=True, allowed_mentions=discord.AllowedMentions.none())

    @app_commands.describe(user="Mention a player or paste their numeric Discord user ID")
    async def grant(self, interaction: discord.Interaction, user: str, reason: str = ""):
        def action():
            recipient = recipient_id(user)
            self.issuer.grant(interaction.user.id, recipient, reason)
            return f"Permanent VIP granted to <@{recipient}>. They can use `/qt claim` with their in-game claim code."
        await self.checked(interaction, action)

    async def claim(self, interaction: discord.Interaction, code: str):
        def action():
            activation = self.issuer.claim(interaction.user.id, code.strip())
            return ("Keep this activation code private. Paste it in QuestTogether's **How to become a VIP** window "
                    "and choose **Activate VIP**.\n```text\n" + activation + "\n```\n"
                    "You can repeat this command to retrieve the same code.")
        await self.checked(interaction, action)

    async def status(self, interaction: discord.Interaction):
        def action():
            status = self.issuer.status(interaction.user.id)
            return ("Your permanent VIP reward is active. Use `/qt claim` for another installation."
                    if status else "No VIP reward yet. DM @chevcast with your contribution for review.")
        await self.checked(interaction, action)

    @app_commands.describe(user="Mention a player or paste their numeric Discord user ID")
    async def issue(self, interaction: discord.Interaction, user: str, code: str):
        def action():
            if str(interaction.user.id) != self.issuer.owner:
                raise ClaimError("Only @chevcast can issue another player's activation.")
            recipient = recipient_id(user)
            activation = self.issuer.claim(recipient, code.strip())
            return f"Send this code privately to <@{recipient}> only:\n```text\n{activation}\n```"
        await self.checked(interaction, action)

    async def command_error(self, interaction, error):
        logging.error("VIP interaction rejected")
        if not interaction.response.is_done():
            await interaction.response.send_message("Unable to process that VIP command.", ephemeral=True)

    async def close(self):
        self.issuer.close()
        await super().close()


async def main():
    async with RewardBot() as bot:
        await bot.start(os.environ["DISCORD_BOT_TOKEN"])


if __name__ == "__main__":
    logging.basicConfig(level=logging.WARNING)
    asyncio.run(main())
