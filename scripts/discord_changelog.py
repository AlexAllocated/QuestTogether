#!/usr/bin/env python3
"""Post canonical QuestTogether release notes with the Bumblebee Discord bot.

Default/--dry-run is offline. --check-access only reads Discord. --post requires
a clean, exact release-tag checkout and a public release with an uploaded ZIP
and successful Tests workflow. Credentials are read only from named env vars.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

sys.dont_write_bytecode = True

from check_release_notes import (
    LUA_FILE, NOTES_FILE, TOC_FILE, NotesError, check_baseline, check_manifest,
    git, parse_notes, previous_release, render_lua, toc_version, unique_object, version_key,
)


# Public destination configuration. Never substitute a webhook for this bot.
EXPECTED_BOT_ID = "890285739940671548"
EXPECTED_GUILD_ID = "1553951084941156502"
EXPECTED_CHANNEL_NAME = "changelog"
CHANNEL_CONFIG = "discord_channels.json"
LOCALIZED_LUA = "LocalizedReleaseNotes.lua"
LOCALE_CHANNEL_NAMES = {
    "enUS": "changelog",
    "deDE": "änderungsprotokoll",
    "frFR": "journal-des-modifications",
    "esES": "registro-de-cambios",
    "esMX": "registro-de-cambios-latam",
    "ptBR": "registro-de-alterações",
    "ruRU": "журнал-изменений",
    "itIT": "registro-modifiche",
    "koKR": "변경-내역",
    "zhCN": "更新日志",
    "zhTW": "更新日誌",
}
DEFAULT_REPOSITORY = "AlexAllocated/QuestTogether"
TEST_WORKFLOW = "test.yml"
DISCORD_API = "https://discord.com/api/v10"
GITHUB_API = "https://api.github.com"
MAX_HISTORY_PAGES = 20
MAX_MESSAGES = 100
MAX_ATTEMPTS = 5
MAX_RETRY_DELAY = 60
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
MAX_ARCHIVE_BYTES = 16 * 1024 * 1024
MAX_ARCHIVE_ENTRY_BYTES = 1024 * 1024
PUBLIC_ASSET_HOSTS = {"github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"}
VIEW_CHANNEL, SEND_MESSAGES, EMBED_LINKS, READ_HISTORY = 1 << 10, 1 << 11, 1 << 14, 1 << 16
REQUIRED_PERMISSIONS = VIEW_CHANNEL | SEND_MESSAGES | EMBED_LINKS | READ_HISTORY


class ChangelogError(ValueError):
    pass


class ReleaseNotReady(ChangelogError):
    pass


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        # Never forward either service's credentials to a redirected host.
        return None


def fetch(method, url, headers, body):
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        response = urllib.request.build_opener(NoRedirect).open(request, timeout=30)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        data = response.read(MAX_RESPONSE_BYTES + 1)
        if len(data) > MAX_RESPONSE_BYTES:
            raise ChangelogError("API response exceeds the size limit")
        return response.code, dict(response.headers.items()), data


class API:
    def __init__(self, base, token, *, transport=fetch, sleep=time.sleep, clock=time.monotonic):
        if not token:
            raise ChangelogError("missing " + ("DISCORD_BOT_TOKEN" if base == DISCORD_API else "GH_TOKEN"))
        if base not in (DISCORD_API, GITHUB_API):
            raise ChangelogError("unsupported API origin")
        self.base, self.token, self.transport, self.sleep, self.clock = base, token, transport, sleep, clock

    def request(self, path, method="GET", payload=None):
        if not path.startswith("/") or path.startswith("//"):
            raise ChangelogError("invalid API path")
        headers = {"Authorization": ("Bot " if self.base == DISCORD_API else "Bearer ") + self.token,
                   "User-Agent": "QuestTogether-release-notes", "Accept": "application/json"}
        if self.base == GITHUB_API:
            headers["X-GitHub-Api-Version"] = "2022-11-28"
        body = None
        if payload is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        deadline = self.clock() + 120
        for attempt in range(MAX_ATTEMPTS):
            if self.clock() >= deadline:
                raise ChangelogError("API retry time window exhausted; inspect history before retrying")
            try:
                status, response_headers, raw = self.transport(method, self.base + path, headers, body)
            except (OSError, urllib.error.URLError):
                # Ambiguous POST results are safe to retry only with a stable nonce.
                if method != "GET" and not (payload and payload.get("enforce_nonce") and payload.get("nonce")):
                    raise ChangelogError("API transport failed; refusing an unsafe retry") from None
                if attempt == MAX_ATTEMPTS - 1:
                    raise ChangelogError("API transport exhausted retries") from None
                self.sleep(min(2 ** attempt, max(0, deadline - self.clock())))
                continue
            try:
                data = json.loads(raw) if raw else None
            except (ValueError, UnicodeError):
                data = None
            if 200 <= status < 300:
                if data is None:
                    raise ChangelogError("API returned no readable JSON")
                return data
            if status != 429 and not 500 <= status < 600:
                # Do not echo response bodies or request headers containing secrets.
                raise ChangelogError("API " + method + " failed with HTTP " + str(status))
            if status >= 500 and method != "GET" and not (payload and payload.get("enforce_nonce") and payload.get("nonce")):
                raise ChangelogError("ambiguous API write failed; refusing an unsafe retry")
            if attempt == MAX_ATTEMPTS - 1:
                raise ChangelogError("API retry limit reached (HTTP " + str(status) + ")")
            delay = 2 ** attempt
            if status == 429:
                retry_after = data.get("retry_after") if isinstance(data, dict) else None
                retry_after = retry_after if retry_after is not None else next(
                    (value for key, value in response_headers.items() if key.lower() == "retry-after"), None)
                try:
                    delay = float(retry_after)
                except (TypeError, ValueError):
                    raise ChangelogError("rate limit response has no valid retry delay") from None
                if not math.isfinite(delay) or not 0 <= delay <= MAX_RETRY_DELAY:
                    raise ChangelogError("rate limit delay exceeds the bounded retry window")
            if self.clock() + delay >= deadline:
                raise ChangelogError("API retry time window exhausted; inspect history before retrying")
            self.sleep(max(0.1, delay))
        raise ChangelogError("API retry limit reached")


def repository_name(value):
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
        raise ChangelogError("invalid GitHub repository")
    return value


def load_notes(root, tag=None, *, exact=False):
    if (root / "scripts/changelogs.py").is_file():
        from changelogs import check as check_changelogs
        check_changelogs(root)
    notes = parse_notes((root / NOTES_FILE).read_text(encoding="utf-8"))
    manifest = (root / TOC_FILE).read_text(encoding="utf-8")
    check_manifest(manifest)
    if notes["version"] != toc_version(manifest):
        raise ChangelogError("canonical notes and TOC versions differ")
    if (root / LUA_FILE).read_bytes() != render_lua(notes).encode("utf-8"):
        raise ChangelogError("ReleaseNotes.lua is stale; regenerate it before releasing")
    if tag is not None and tag != "v" + notes["version"]:
        raise ChangelogError("tag does not match the canonical release-note version")
    check_baseline(root, notes, previous_release(root, notes["version"]))
    sha = git(root, "rev-parse", "HEAD").stdout.strip()
    if exact:
        if not tag:
            raise ChangelogError("--post requires --tag")
        tagged = git(root, "rev-parse", "--verify", "--end-of-options", "refs/tags/" + tag + "^{commit}").stdout.strip()
        if tagged != sha or git(root, "status", "--porcelain", "--untracked-files=no").stdout.strip():
            raise ChangelogError("use a clean checkout of the exact release tag")
    return notes, sha


def canonical_locale(locale):
    if locale not in LOCALE_CHANNEL_NAMES:
        raise ChangelogError("unsupported changelog locale")
    return locale


def load_channel_config(root, *, allow_unconfigured=False):
    config = json.loads((root / CHANNEL_CONFIG).read_text(encoding="utf-8"), object_pairs_hook=unique_object)
    if (not isinstance(config, dict) or set(config) != {"guild_id", "bot_id", "channels"}
            or config["guild_id"] != EXPECTED_GUILD_ID or config["bot_id"] != EXPECTED_BOT_ID
            or not isinstance(config["channels"], dict) or set(config["channels"]) != set(LOCALE_CHANNEL_NAMES)):
        raise ChangelogError("invalid localized Discord guild/bot/channel configuration")
    ids = set()
    for locale, name in LOCALE_CHANNEL_NAMES.items():
        entry = config["channels"][locale]
        if not isinstance(entry, dict) or set(entry) != {"id", "name"} or entry["name"] != name:
            raise ChangelogError("channel name does not match the locale allowlist")
        identifier = entry["id"]
        if identifier is None and allow_unconfigured and locale != "enUS":
            continue
        snowflake(identifier)
        if identifier in ids:
            raise ChangelogError("localized Discord channels must have distinct IDs")
        ids.add(identifier)
    return config


def channel_targets(root, locales):
    config = load_channel_config(root) if (root / CHANNEL_CONFIG).exists() else None
    targets = {}
    for locale in locales:
        locale = canonical_locale(locale)
        if locale == "enUS" and os.environ.get("DISCORD_CHANGELOG_CHANNEL_ID"):
            identifier = snowflake(os.environ["DISCORD_CHANGELOG_CHANNEL_ID"])
            if config and config["channels"][locale]["id"] != identifier:
                raise ChangelogError("English channel environment override differs from the reviewed configuration")
        elif config:
            identifier = config["channels"][locale]["id"]
        else:
            raise ChangelogError("Discord destination is not configured for " + locale)
        targets[locale] = identifier
    if len(set(targets.values())) != len(targets):
        raise ChangelogError("localized Discord channels must have distinct IDs")
    return targets


def load_localized_notes(root, source, *, check_generated=True):
    # Shared validator rejects stale source digests, mismatched versions and
    # dropped/added sections or items. Never translate or summarize while posting.
    from localization import release_note_outputs
    outputs = release_note_outputs(root, source)
    expected = outputs[root / LOCALIZED_LUA].encode("utf-8")
    if check_generated and (root / LOCALIZED_LUA).read_bytes() != expected:
        raise ChangelogError(LOCALIZED_LUA + " is stale; regenerate it before releasing")
    translated = {}
    for locale in LOCALE_CHANNEL_NAMES:
        if locale == "enUS":
            continue
        path = root / "release_notes" / (locale + ".json")
        raw = outputs.get(path)
        wrapper = json.loads(raw if raw is not None else path.read_text(encoding="utf-8"))
        translated[locale] = parse_notes(json.dumps(wrapper["notes"], ensure_ascii=False))
        if translated[locale]["version"] != source["version"]:
            raise ChangelogError("localized release-note version differs from English")
    return translated, expected


def text_length(value):
    # Conservative UTF-16 accounting also keeps astral Unicode within limits.
    return len(value.encode("utf-16-le")) // 2


def embed_length(embed):
    return sum(text_length(embed.get(key, "")) for key in ("title", "description")) + text_length(
        embed.get("footer", {}).get("text", ""))


def release_key(repository, tag, locale="enUS"):
    locale = canonical_locale(locale)
    key = "QuestTogether release " + repository + "@" + tag
    return key if locale == "enUS" else key + " [" + locale + "]"


def build_messages(notes, repository, tag, locale="enUS"):
    from changelogs import illustration_images

    repository_name(repository)
    if tag != "v" + notes["version"]:
        raise ChangelogError("tag and notes version differ")
    url = "https://github.com/" + repository + "/releases/tag/" + tag
    embeds = [{"title": "QuestTogether " + tag, "description": notes["welcome"]}]
    for section in notes["sections"]:
        description = ""
        for item in section["items"]:
            bullet = "- " + item
            combined = description + ("\n" if description else "") + bullet
            if text_length(combined) > 4096:
                embeds.append({"title": section["title"], "description": description})
                description = bullet
            else:
                description = combined
        embeds.append({"title": section["title"], "description": description})
        for client, asset in illustration_images(section.get("illustration")):
            embeds.append({"title": section["title"], "description": client,
                           "image": {"url": "https://raw.githubusercontent.com/" + repository + "/" + tag
                                     + "/Media/ReleaseNotes/" + asset + ".png"}})
    # Reserve the longest possible footer before packing. No item is truncated
    # or split, and no release URL occurs twice within the same message.
    digest = hashlib.sha256(json.dumps(notes, sort_keys=True, ensure_ascii=False).encode("utf-8")).hexdigest()[:16]
    key = release_key(repository, tag, locale)
    reserve = text_length(key + " | part 100/100 | " + digest)
    groups, current = [], []
    for embed in embeds:
        if not embed["description"] or text_length(embed["description"]) > 4096 or text_length(embed["title"]) > 256:
            raise ChangelogError("a canonical note cannot fit within an embed")
        if current and (len(current) == 10 or sum(map(embed_length, current)) + embed_length(embed) + reserve > 6000):
            groups.append(current)
            current = []
        current.append(embed)
    if current:
        groups.append(current)
    if len(groups) > MAX_MESSAGES:
        raise ChangelogError("release notes exceed the message limit")
    messages = []
    for index, group in enumerate(groups, 1):
        marker = key + " | part " + str(index) + "/" + str(len(groups)) + " | " + digest
        group[0]["url"] = url
        group[-1]["footer"] = {"text": marker}
        if sum(map(embed_length, group)) > 6000:
            raise ChangelogError("release message exceeds Discord's text budget")
        nonce = hashlib.sha256((key + "|" + str(index)).encode("utf-8")).hexdigest()[:24]
        messages.append({"embeds": group, "allowed_mentions": {"parse": [], "users": [], "roles": [], "replied_user": False},
                         "nonce": nonce, "enforce_nonce": True})
    return messages


def snowflake(value):
    if not isinstance(value, str) or not re.fullmatch(r"[1-9][0-9]{16,19}", value):
        raise ChangelogError("invalid Discord ID")
    return value


def permissions(guild, member, channel):
    roles = {role["id"]: int(role["permissions"]) for role in guild["roles"]}
    role_ids = set(member["roles"])
    value = roles[EXPECTED_GUILD_ID]
    for role_id in role_ids:
        value |= roles[role_id]
    if guild.get("owner_id") == EXPECTED_BOT_ID or value & (1 << 3):
        return REQUIRED_PERMISSIONS
    overwrites = channel["permission_overwrites"]
    for overwrite in overwrites:
        if overwrite["type"] == 0 and overwrite["id"] == EXPECTED_GUILD_ID:
            value = (value & ~int(overwrite["deny"])) | int(overwrite["allow"])
    allow = deny = 0
    for overwrite in overwrites:
        if overwrite["type"] == 0 and overwrite["id"] in role_ids:
            allow |= int(overwrite["allow"])
            deny |= int(overwrite["deny"])
    value = (value & ~deny) | allow
    for overwrite in overwrites:
        if overwrite["type"] == 1 and overwrite["id"] == EXPECTED_BOT_ID:
            value = (value & ~int(overwrite["deny"])) | int(overwrite["allow"])
    return value


def verify_access(api, channel_id, locale="enUS"):
    locale = canonical_locale(locale)
    snowflake(channel_id)
    user = api.request("/users/@me")
    if user.get("id") != EXPECTED_BOT_ID or user.get("bot") is not True:
        raise ChangelogError("token does not belong to the expected Bumblebee bot")
    channel = api.request("/channels/" + channel_id)
    if channel.get("id") != channel_id or channel.get("guild_id") != EXPECTED_GUILD_ID:
        raise ChangelogError("changelog channel belongs to the wrong guild")
    if channel.get("name") != LOCALE_CHANNEL_NAMES[locale] or channel.get("type") not in (0, 5):
        raise ChangelogError("destination must be the allowlisted guild text/announcement channel for " + locale)
    guild = api.request("/guilds/" + EXPECTED_GUILD_ID)
    member = api.request("/guilds/" + EXPECTED_GUILD_ID + "/members/" + EXPECTED_BOT_ID)
    if guild.get("id") != EXPECTED_GUILD_ID or member.get("user", {}).get("id") != EXPECTED_BOT_ID:
        raise ChangelogError("could not verify guild membership")
    timeout = member.get("communication_disabled_until")
    if member.get("pending") is True or (timeout and datetime.fromisoformat(timeout.replace("Z", "+00:00")) > datetime.now(timezone.utc)):
        raise ChangelogError("bot membership is pending or timed out")
    try:
        effective = permissions(guild, member, channel)
    except (KeyError, TypeError, ValueError):
        raise ChangelogError("could not determine bot channel permissions") from None
    if effective & REQUIRED_PERMISSIONS != REQUIRED_PERMISSIONS:
        raise ChangelogError("bot needs View Channel, Send Messages, Embed Links and Read Message History")
    return channel


def read_history(api, channel_id, max_pages=MAX_HISTORY_PAGES):
    messages, before = [], None
    for _ in range(max_pages):
        path = "/channels/" + channel_id + "/messages?limit=100" + ("&before=" + before if before else "")
        batch = api.request(path)
        if not isinstance(batch, list) or len(batch) > 100:
            raise ChangelogError("invalid Discord history page")
        previous = int(before) if before else None
        for message in batch:
            identifier = int(snowflake(message.get("id")))
            if message.get("channel_id") != channel_id or (previous is not None and identifier >= previous):
                raise ChangelogError("Discord history did not advance in this channel")
            previous = identifier
        messages.extend(batch)
        if len(batch) < 100:
            return messages
        before = batch[-1]["id"]
    raise ChangelogError("Discord history scan limit reached; refusing to risk duplicate posts")


def posted_markers(history, planned, repository, tag, locale="enUS"):
    expected = {message["embeds"][-1]["footer"]["text"] for message in planned}
    found = set()
    prefix = release_key(repository, tag, locale) + " | "
    for message in history:
        author = message.get("author", {})
        if author.get("id") != EXPECTED_BOT_ID or author.get("bot") is not True or message.get("webhook_id"):
            continue
        for embed in message.get("embeds", []):
            marker = embed.get("footer", {}).get("text", "")
            if marker.startswith(prefix):
                if marker not in expected:
                    raise ChangelogError("existing release markers differ from the canonical notes; inspect before retrying")
                found.add(marker)
    return found


def post_missing(api, channel_id, planned, history, repository, tag, locale="enUS"):
    found = posted_markers(history, planned, repository, tag, locale)
    count = 0
    for payload in planned:
        marker = payload["embeds"][-1]["footer"]["text"]
        if marker in found:
            continue
        result = api.request("/channels/" + channel_id + "/messages", "POST", payload)
        if result.get("channel_id") != channel_id or marker not in posted_markers([result], planned, repository, tag, locale):
            raise ChangelogError("Discord did not confirm the expected bot-authored release part")
        found.add(marker)
        count += 1
    return count


def remote_tag_sha(api, prefix, tag):
    ref = api.request(prefix + "/git/ref/tags/" + tag)
    if ref.get("ref") != "refs/tags/" + tag:
        raise ChangelogError("GitHub returned the wrong release tag")
    target = ref.get("object", {})
    for _ in range(5):
        sha = target.get("sha", "")
        if not re.fullmatch(r"[0-9a-f]{40}", sha):
            break
        if target.get("type") == "commit":
            return sha
        if target.get("type") != "tag":
            break
        target = api.request(prefix + "/git/tags/" + sha).get("object", {})
    raise ChangelogError("cannot resolve the published tag to a commit")


def release_archive(release, repository, tag):
    names = {"QuestTogether-" + tag + ".zip", "QuestTogether-" + tag[1:] + ".zip"}
    assets = [asset for asset in release.get("assets", [])
              if asset.get("state") == "uploaded" and asset.get("name") in names
              and type(asset.get("size")) is int and asset["size"] > 0
              and asset.get("browser_download_url") == "https://github.com/" + repository
              + "/releases/download/" + tag + "/" + asset["name"]]
    if not assets:
        raise ReleaseNotReady("published release is waiting for its uploaded QuestTogether versioned ZIP")
    if len(assets) != 1 or assets[0]["size"] > MAX_ARCHIVE_BYTES:
        raise ChangelogError("release ZIP is ambiguous or exceeds the download limit")
    return assets[0]


def public_asset_url(url):
    parsed = urllib.parse.urlsplit(url)
    if (parsed.scheme != "https" or parsed.hostname not in PUBLIC_ASSET_HOSTS
            or parsed.username or parsed.password or parsed.port not in (None, 443)):
        raise ChangelogError("release ZIP redirected outside the public GitHub asset hosts")
    return url


class PublicAssetRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, new_url):
        public_asset_url(new_url)
        return super().redirect_request(request, fp, code, message, headers, new_url)


def download_archive(url, size):
    # This opener has no GitHub or Discord authorization, including on redirects.
    request = urllib.request.Request(public_asset_url(url), headers={"User-Agent": "QuestTogether-release-notes"})
    try:
        with urllib.request.build_opener(PublicAssetRedirect).open(request, timeout=30) as response:
            if response.code != 200:
                raise ChangelogError("release ZIP download did not succeed")
            data = response.read(min(size, MAX_ARCHIVE_BYTES) + 1)
    except (OSError, urllib.error.URLError):
        raise ChangelogError("public release ZIP download failed") from None
    if len(data) != size or len(data) > MAX_ARCHIVE_BYTES:
        raise ChangelogError("release ZIP size differs from its published asset metadata")
    return data


def verify_archive(release, repository, tag, notes, *, download=download_archive, localized_lua=None):
    asset = release_archive(release, repository, tag)
    data = download(asset["browser_download_url"], asset["size"])
    if len(data) != asset["size"] or len(data) > MAX_ARCHIVE_BYTES:
        raise ChangelogError("release ZIP size differs from its published asset metadata")
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            entries = archive.infolist()
            if len(entries) > 1000:
                raise ChangelogError("release ZIP has too many entries")
            # No extraction: reject duplicate/ambiguous paths before reading only
            # these bounded files, including Windows case/backslash aliases.
            seen = set()
            for entry in entries:
                name = entry.filename.replace("\\", "/").rstrip("/")
                parts = name.split("/")
                if any(part in ("", ".", "..") for part in parts) or name.casefold() in seen:
                    raise ChangelogError("release ZIP contains duplicate or ambiguous paths")
                seen.add(name.casefold())
            contents = {}
            for name in (TOC_FILE, LUA_FILE) + ((LOCALIZED_LUA,) if localized_lua is not None else ()):
                info = archive.getinfo("QuestTogether/" + name)
                if info.file_size > MAX_ARCHIVE_ENTRY_BYTES or info.flag_bits & 1:
                    raise ChangelogError("release ZIP note files are too large or encrypted")
                contents[name] = archive.read(info)
    except (zipfile.BadZipFile, KeyError, RuntimeError, NotImplementedError):
        raise ChangelogError("release ZIP is invalid or missing QuestTogether's note files") from None
    manifest = contents[TOC_FILE].decode("utf-8")
    check_manifest(manifest)
    if toc_version(manifest) != notes["version"] or contents[LUA_FILE] != render_lua(notes).encode("utf-8"):
        raise ChangelogError("published ZIP notes/version differ from the canonical release notes")
    if localized_lua is not None:
        entries = [line.strip().replace("\\", "/") for line in manifest.splitlines()
                   if line.strip() and not line.lstrip().startswith("#")]
        if (entries.count(LOCALIZED_LUA) != 1 or entries.index(LOCALIZED_LUA) < entries.index(LUA_FILE)
                or contents[LOCALIZED_LUA] != localized_lua):
            raise ChangelogError("published ZIP localized notes differ or are not loaded after English notes")


def verify_release(api, repository, tag, sha):
    prefix = "/repos/" + repository_name(repository)
    repo = api.request(prefix)
    if repo.get("full_name", "").casefold() != repository.casefold() or repo.get("private") is not False:
        raise ChangelogError("release posting requires the expected public repository")
    if remote_tag_sha(api, prefix, tag) != sha:
        raise ChangelogError("local checkout differs from the public release tag")
    release = api.request(prefix + "/releases/tags/" + tag)
    if (release.get("tag_name") != tag or release.get("draft") is not False or not release.get("published_at")
            or release.get("html_url") != "https://github.com/" + repository + "/releases/tag/" + tag):
        raise ChangelogError("release is not publicly published at the expected URL")
    version_key(tag.removeprefix("v"))
    release_archive(release, repository, tag)
    runs = api.request(prefix + "/actions/workflows/" + TEST_WORKFLOW + "/runs?" + urllib.parse.urlencode(
        {"head_sha": sha, "event": "push", "per_page": 100}))
    eligible = [run for run in runs.get("workflow_runs", [])
                if run.get("head_sha") == sha and run.get("event") == "push"
                and run.get("path") == ".github/workflows/" + TEST_WORKFLOW
                and run.get("head_repository", {}).get("full_name", "").casefold() == repository.casefold()]
    if not eligible:
        raise ReleaseNotReady("no push Tests workflow has run for the release commit")
    latest = max(eligible, key=lambda run: run["id"])
    if latest.get("status") != "completed":
        raise ReleaseNotReady("Tests workflow is still running for the release commit")
    if latest.get("conclusion") != "success":
        raise ChangelogError("latest Tests workflow did not succeed for the release commit")
    return release


def wait_for_release(api, repository, tag, sha, wait_seconds, *, clock=time.monotonic, sleep=time.sleep):
    deadline = clock() + wait_seconds
    while True:
        try:
            return verify_release(api, repository, tag, sha)
        except ReleaseNotReady:
            remaining = deadline - clock()
            if remaining <= 0:
                raise
            sleep(min(15, remaining))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument("--dry-run", action="store_true", help="validate/render locally without API calls (default)")
    modes.add_argument("--check-access", action="store_true", help="read-only Discord destination and history verification")
    modes.add_argument("--post", action="store_true", help="publish missing parts of a verified public release")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--tag", help="exact release tag; required for --post")
    parser.add_argument("--repository", default=DEFAULT_REPOSITORY)
    locales = parser.add_mutually_exclusive_group()
    locales.add_argument("--locale", default="enUS", choices=[*LOCALE_CHANNEL_NAMES])
    locales.add_argument("--all-locales", action="store_true", help="validate and post English plus all ten translations")
    parser.add_argument("--wait-seconds", type=int, default=0, help="wait up to 600 seconds for the release ZIP/tests")
    args = parser.parse_args(argv)
    try:
        if not 0 <= args.wait_seconds <= 600:
            raise ChangelogError("--wait-seconds must be between 0 and 600")
        repository = repository_name(args.repository)
        root = args.root.resolve()
        locales = list(LOCALE_CHANNEL_NAMES) if args.all_locales else [canonical_locale(args.locale)]
        if args.check_access:
            api = API(DISCORD_API, os.environ.get("DISCORD_BOT_TOKEN"))
            for locale, channel_id in channel_targets(root, locales).items():
                verify_access(api, channel_id, locale)
                history = read_history(api, channel_id)
                print("Verified Bumblebee bot in guild " + EXPECTED_GUILD_ID + " / #" + LOCALE_CHANNEL_NAMES[locale]
                      + " (" + channel_id + "); read " + str(len(history)) + " messages. No messages sent.")
            return 0
        notes, sha = load_notes(root, args.tag, exact=args.post or args.tag is not None)
        tag = args.tag or "v" + notes["version"]
        localized_lua = None
        all_notes = {"enUS": notes}
        manifest_entries = {line.strip().replace("\\", "/") for line in (root / TOC_FILE).read_text(encoding="utf-8").splitlines()}
        if locales != ["enUS"] or (root / LOCALIZED_LUA).exists() or LOCALIZED_LUA in manifest_entries:
            translated, localized_lua = load_localized_notes(root, notes)
            all_notes.update(translated)
        planned = {locale: build_messages(all_notes[locale], repository, tag, locale) for locale in locales}
        if not args.post:
            print(json.dumps(planned if args.all_locales else planned[locales[0]], ensure_ascii=False, indent=2))
            return 0
        github = API(GITHUB_API, os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN"))
        release = wait_for_release(github, repository, tag, sha, args.wait_seconds)
        verify_archive(release, repository, tag, notes, localized_lua=localized_lua)
        discord = API(DISCORD_API, os.environ.get("DISCORD_BOT_TOKEN"))
        targets = channel_targets(root, locales)
        histories = {}
        # Validate every target and history before the first externally visible
        # write. A later transport failure can safely resume only missing parts.
        for locale, channel_id in targets.items():
            verify_access(discord, channel_id, locale)
            histories[locale] = read_history(discord, channel_id)
            posted_markers(histories[locale], planned[locale], repository, tag, locale)
        for locale, channel_id in targets.items():
            posted = post_missing(discord, channel_id, planned[locale], histories[locale], repository, tag, locale)
            print("Release " + tag + " " + locale + ": posted " + str(posted) + " missing parts; "
                  + str(len(planned[locale]) - posted) + " already present.")
        return 0
    except (ChangelogError, NotesError, OSError, UnicodeError, KeyError, TypeError, AttributeError, ValueError, ImportError) as error:
        # API errors deliberately omit response bodies and headers. No token is logged.
        print("Discord changelog error: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
