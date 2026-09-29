#!/usr/bin/env python3
"""Provision QT's translated changelog channels, or backfill only published 5.13.1.

Default mode only reads channel configuration. --create creates missing channels
with the English channel's category and overwrites, then records their public IDs.
--post-current is a one-time migration for the pre-localization 5.13.1 archive;
all future releases must use discord_changelog.py's exact localized ZIP checks.
"""

import argparse
import json
import os
from pathlib import Path
import re
import sys

sys.dont_write_bytecode = True
import discord_changelog as changelog

CURRENT_BACKFILL_TAG = "v5.13.1"


def bot_token(env_file=None):
    value = os.environ.get("DISCORD_BOT_TOKEN")
    if value:
        return value
    if env_file is None:
        raise changelog.ChangelogError("DISCORD_BOT_TOKEN is required")
    values = []
    with env_file.open(encoding="utf-8") as handle:
        for line in handle:
            match = re.match(r"^\s*(?:export\s+)?DISCORD_BOT_TOKEN\s*=\s*(.*?)\s*$", line)
            if match:
                value = match[1]
                if value[:1] in ('"', "'") and value[-1:] == value[:1]:
                    value = value[1:-1]
                if not re.fullmatch(r"[A-Za-z0-9._-]+", value):
                    raise changelog.ChangelogError("bot token entry has an unsupported format")
                values.append(value)
    if len(values) != 1:
        raise changelog.ChangelogError("environment file must contain exactly one bot token entry")
    return values[0]


def overwrites(channel):
    result = []
    for entry in channel["permission_overwrites"]:
        if entry.get("type") not in (0, 1):
            raise changelog.ChangelogError("invalid source channel permission overwrite")
        identifier = changelog.snowflake(entry.get("id"))
        if not all(isinstance(entry.get(key), str) and entry[key].isdigit() for key in ("allow", "deny")):
            raise changelog.ChangelogError("invalid source channel permission bits")
        result.append({"id": identifier, "type": entry["type"], "allow": entry["allow"], "deny": entry["deny"]})
    return sorted(result, key=lambda entry: (entry["type"], entry["id"]))


def verify_template(channel, template):
    if (channel.get("type") != template["type"] or channel.get("parent_id") != template.get("parent_id")
            or channel.get("nsfw", False) != template.get("nsfw", False)
            or overwrites(channel) != overwrites(template)):
        raise changelog.ChangelogError("existing localized channel differs from the English category/permissions")


def provision(api, root, *, create=False):
    config = changelog.load_channel_config(root, allow_unconfigured=True)
    template_id = config["channels"]["enUS"]["id"]
    template = changelog.verify_access(api, template_id)
    parent = template.get("parent_id")
    if parent is not None:
        changelog.snowflake(parent)
        category = api.request("/channels/" + parent)
        if category.get("type") != 4 or category.get("guild_id") != changelog.EXPECTED_GUILD_ID:
            raise changelog.ChangelogError("English channel category is outside the expected guild")
    channels = api.request("/guilds/" + changelog.EXPECTED_GUILD_ID + "/channels")
    if not isinstance(channels, list) or len(channels) > 500:
        raise changelog.ChangelogError("invalid guild channel list")
    selected, missing = {}, []
    for locale, name in changelog.LOCALE_CHANNEL_NAMES.items():
        matches = [channel for channel in channels if channel.get("name") == name]
        if len(matches) > 1:
            raise changelog.ChangelogError("ambiguous existing channel name: " + name)
        configured_id = config["channels"][locale]["id"]
        if matches:
            identifier = changelog.snowflake(matches[0].get("id"))
            if configured_id is not None and configured_id != identifier:
                raise changelog.ChangelogError("configured channel ID differs from the existing localized channel")
            channel = changelog.verify_access(api, identifier, locale)
            verify_template(channel, template)
            selected[locale] = identifier
        elif configured_id is not None:
            raise changelog.ChangelogError("configured channel is missing or renamed: " + name)
        else:
            missing.append(locale)
    # Resolve every existing name/ID before the first mutation. No attempt is
    # made to change permissions on an existing channel or any other guild.
    if create and missing:
        guild = api.request("/guilds/" + changelog.EXPECTED_GUILD_ID)
        member = api.request("/guilds/" + changelog.EXPECTED_GUILD_ID + "/members/" + changelog.EXPECTED_BOT_ID)
        role_ids = {changelog.EXPECTED_GUILD_ID, *member["roles"]}
        bits = 0
        for role in guild["roles"]:
            if role["id"] in role_ids:
                bits |= int(role["permissions"])
        if guild.get("owner_id") != changelog.EXPECTED_BOT_ID and not bits & ((1 << 3) | (1 << 4)):
            raise changelog.ChangelogError("bot needs Manage Channels to create localized destinations")
    for locale in missing:
        name = changelog.LOCALE_CHANNEL_NAMES[locale]
        if not create:
            print("Missing " + locale + " channel #" + name + "; use --create to provision.")
            continue
        payload = {"name": name, "type": template["type"], "parent_id": parent,
                   "permission_overwrites": overwrites(template), "nsfw": template.get("nsfw", False),
                   "rate_limit_per_user": template.get("rate_limit_per_user", 0)}
        # Channel creation has no nonce contract. Ambiguous failures stop; a
        # subsequent invocation rediscovers the name instead of blind retries.
        result = api.request("/guilds/" + changelog.EXPECTED_GUILD_ID + "/channels", "POST", payload)
        identifier = changelog.snowflake(result.get("id"))
        channel = changelog.verify_access(api, identifier, locale)
        verify_template(channel, template)
        selected[locale] = identifier
        print("Created " + locale + " #" + name + " (" + identifier + ").")
    if create:
        for locale, identifier in selected.items():
            config["channels"][locale]["id"] = identifier
        (root / changelog.CHANNEL_CONFIG).write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return selected


def post_current(root, published_root, discord, github):
    if published_root is None:
        raise changelog.ChangelogError("--post-current requires --published-root with a clean v5.13.1 checkout")
    tag = CURRENT_BACKFILL_TAG
    source, sha = changelog.load_notes(published_root.resolve(), tag, exact=True)
    current = changelog.parse_notes((root / changelog.NOTES_FILE).read_text(encoding="utf-8"))
    if current != source:
        raise changelog.ChangelogError("backfill translations must match the published 5.13.1 English source")
    translated, _ = changelog.load_localized_notes(root, source)
    locales = list(translated)
    repository = changelog.DEFAULT_REPOSITORY
    planned = {locale: changelog.build_messages(translated[locale], repository, tag, locale) for locale in locales}
    release = changelog.verify_release(github, repository, tag, sha)
    # This one published ZIP predates localized notes. Still verify the exact
    # canonical English notes and its native TOC before any translated post.
    changelog.verify_archive(release, repository, tag, source)
    targets = changelog.channel_targets(root, locales)
    histories = {}
    for locale, identifier in targets.items():
        changelog.verify_access(discord, identifier, locale)
        histories[locale] = changelog.read_history(discord, identifier)
        changelog.posted_markers(histories[locale], planned[locale], repository, tag, locale)
    for locale, identifier in targets.items():
        count = changelog.post_missing(discord, identifier, planned[locale], histories[locale], repository, tag, locale)
        print("Published " + tag + " " + locale + ": " + str(count) + " missing parts posted.")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--create", action="store_true")
    modes.add_argument("--post-current", action="store_true")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--published-root", type=Path)
    parser.add_argument("--token-env-file", type=Path, help="optional local environment file; only DISCORD_BOT_TOKEN is read")
    args = parser.parse_args(argv)
    try:
        discord = changelog.API(changelog.DISCORD_API, bot_token(args.token_env_file))
        root = args.root.resolve()
        if args.post_current:
            github = changelog.API(changelog.GITHUB_API, os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"))
            post_current(root, args.published_root, discord, github)
        else:
            selected = provision(discord, root, create=args.create)
            print("Verified " + str(len(selected)) + " configured locale channels. No messages sent.")
        return 0
    except (changelog.ChangelogError, changelog.NotesError, OSError, ValueError, KeyError, TypeError, ImportError) as error:
        print("Localized Discord setup error: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
