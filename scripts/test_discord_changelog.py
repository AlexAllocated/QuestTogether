#!/usr/bin/env python3
"""Offline Discord release contracts: private API doubles and temporary Git repos."""

import contextlib
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import sys
import zipfile

sys.dont_write_bytecode = True

import discord_changelog as changelog
import setup_localized_discord as setup
import localization


CHANNEL = "1553981217039187978"
SHA = "a" * 40
REPO = changelog.DEFAULT_REPOSITORY
TAG = "v1.2.4"


def setUpModule():
    # A missing injection must fail the test, never contact either real service.
    global network_guard
    network_guard = patch.object(changelog.urllib.request.OpenerDirector, "open",
                                 side_effect=AssertionError("offline test attempted network access"))
    network_guard.start()


def tearDownModule():
    network_guard.stop()


def notes(version="1.2.4", item="Compare eligible quests with a selected player."):
    return {"version": version, "welcome": "Welcome to QuestTogether. @everyone <@123456789012345678>",
            "sections": [{"title": "Party quests", "items": [item]}]}


def response(payload, author=None, *, identifier="1554000000000000000", webhook=None):
    result = {"id": identifier, "channel_id": CHANNEL, "embeds": copy.deepcopy(payload["embeds"]),
              "author": author or {"id": changelog.EXPECTED_BOT_ID, "bot": True}}
    if webhook:
        result["webhook_id"] = webhook
    return result


class Discord:
    def __init__(self):
        self.channel = {"id": CHANNEL, "guild_id": changelog.EXPECTED_GUILD_ID,
                        "name": "changelog", "type": 0, "permission_overwrites": []}
        self.user = {"id": changelog.EXPECTED_BOT_ID, "bot": True}
        self.guild = {"id": changelog.EXPECTED_GUILD_ID, "owner_id": "1554000000000000001",
                      "roles": [{"id": changelog.EXPECTED_GUILD_ID, "permissions": str(changelog.REQUIRED_PERMISSIONS)},
                                {"id": "1554000000000000002", "permissions": "0"}]}
        self.member = {"user": self.user, "roles": ["1554000000000000002"]}
        self.history, self.calls, self.posts = [], [], []
        self.fail_part = None

    def request(self, path, method="GET", payload=None):
        self.calls.append((path, method, copy.deepcopy(payload)))
        if method == "POST":
            if self.fail_part == len(self.posts) + 1:
                raise changelog.ChangelogError("injected partial transport failure")
            self.posts.append(copy.deepcopy(payload))
            result = response(payload, identifier=str(1554000000000000000 + len(self.posts)))
            self.history.insert(0, result)
            return result
        routes = {"/users/@me": self.user, "/channels/" + CHANNEL: self.channel,
                  "/guilds/" + changelog.EXPECTED_GUILD_ID: self.guild,
                  "/guilds/" + changelog.EXPECTED_GUILD_ID + "/members/" + changelog.EXPECTED_BOT_ID: self.member}
        if path.startswith("/channels/" + CHANNEL + "/messages?"):
            return copy.deepcopy(self.history)
        return copy.deepcopy(routes[path])


class GitHub:
    def __init__(self, sha=SHA):
        self.sha = sha
        self.repo = {"full_name": REPO, "private": False}
        self.ref = {"ref": "refs/tags/" + TAG, "object": {"sha": sha, "type": "commit"}}
        self.release = {"tag_name": TAG, "draft": False, "published_at": "2026-09-27T12:00:00Z",
                        "html_url": "https://github.com/" + REPO + "/releases/tag/" + TAG,
                        "assets": [{"name": "QuestTogether-" + TAG + ".zip", "state": "uploaded", "size": 1024,
                                    "browser_download_url": "https://github.com/" + REPO + "/releases/download/" + TAG + "/QuestTogether-" + TAG + ".zip"}]}
        self.runs = [{"id": 1, "head_sha": sha, "event": "push", "path": ".github/workflows/test.yml",
                      "head_repository": {"full_name": REPO}, "status": "completed", "conclusion": "success"}]
        self.calls = []

    def request(self, path, method="GET", payload=None):
        self.calls.append((path, method))
        if method != "GET":
            raise AssertionError("GitHub must remain read-only")
        prefix = "/repos/" + REPO
        if path == prefix:
            return copy.deepcopy(self.repo)
        if path == prefix + "/git/ref/tags/" + TAG:
            return copy.deepcopy(self.ref)
        if path == prefix + "/git/tags/" + "b" * 40:
            return {"object": {"sha": self.sha, "type": "commit"}}
        if path == prefix + "/releases/tags/" + TAG:
            return copy.deepcopy(self.release)
        if path.startswith(prefix + "/actions/workflows/test.yml/runs?"):
            return {"workflow_runs": copy.deepcopy(self.runs)}
        raise AssertionError(path)


def locale_config(*, configured=True):
    return {"guild_id": changelog.EXPECTED_GUILD_ID, "bot_id": changelog.EXPECTED_BOT_ID,
            "channels": {locale: {"id": CHANNEL if locale == "enUS" else
                                   (str(1555000000000000000 + index) if configured else None), "name": name}
                         for index, (locale, name) in enumerate(changelog.LOCALE_CHANNEL_NAMES.items())}}


class LocalizedDiscord(Discord):
    def __init__(self, *, existing=True):
        super().__init__()
        self.guild["roles"][0]["permissions"] = str(changelog.REQUIRED_PERMISSIONS | (1 << 4))
        self.config = locale_config()
        self.channels = {entry["id"]: dict(copy.deepcopy(self.channel), id=entry["id"], name=entry["name"])
                         for locale, entry in self.config["channels"].items() if existing or locale == "enUS"}
        self.histories = {identifier: [] for identifier in self.channels}

    def request(self, path, method="GET", payload=None):
        if path == "/guilds/" + changelog.EXPECTED_GUILD_ID + "/channels":
            self.calls.append((path, method, copy.deepcopy(payload)))
            if method == "GET":
                return list(copy.deepcopy(self.channels).values())
            self.posts.append(copy.deepcopy(payload))
            identifier = next(entry["id"] for entry in self.config["channels"].values() if entry["name"] == payload["name"])
            channel = dict(copy.deepcopy(payload), id=identifier, guild_id=changelog.EXPECTED_GUILD_ID)
            self.channels[identifier] = channel
            self.histories[identifier] = []
            return channel
        if path.startswith("/channels/"):
            identifier = path.split("/")[2]
            self.calls.append((path, method, copy.deepcopy(payload)))
            if method == "POST":
                if self.fail_part == len(self.posts) + 1:
                    raise changelog.ChangelogError("injected partial locale failure")
                self.posts.append(copy.deepcopy(payload))
                result = response(payload, identifier=str(1556000000000000000 + len(self.posts)))
                result["channel_id"] = identifier
                self.histories[identifier].insert(0, result)
                return result
            if "/messages?" in path:
                return copy.deepcopy(self.histories[identifier])
            return copy.deepcopy(self.channels[identifier])
        return super().request(path, method, payload)


def write_translations(root, source):
    (root / "release_notes").mkdir(exist_ok=True)
    for locale in localization.LOCALES:
        translated = copy.deepcopy(source)
        translated["welcome"] = locale + ": " + translated["welcome"]
        wrapper = {"source_sha256": localization.digest(source), "notes": translated}
        (root / "release_notes" / (locale + ".json")).write_text(json.dumps(wrapper), encoding="utf-8")
    for path, value in localization.release_note_outputs(root, source).items():
        path.write_text(value, encoding="utf-8")
    (root / changelog.CHANNEL_CONFIG).write_text(json.dumps(locale_config()), encoding="utf-8")


class FormattingTests(unittest.TestCase):
    def test_locales_have_distinct_markers_and_nonces_with_distinct_spanish_locales(self):
        english = changelog.build_messages(notes(), REPO, TAG)
        self.assertEqual(changelog.release_key(REPO, TAG), "QuestTogether release " + REPO + "@" + TAG)
        planned = {locale: changelog.build_messages(notes(), REPO, TAG, locale)
                   for locale in changelog.LOCALE_CHANNEL_NAMES}
        self.assertEqual(planned["enUS"], english)
        self.assertNotEqual(planned["esMX"], planned["esES"])
        self.assertEqual(changelog.canonical_locale("esMX"), "esMX")
        self.assertEqual(len({messages[0]["nonce"] for messages in planned.values()}),len(changelog.LOCALE_CHANNEL_NAMES))
        self.assertEqual(changelog.posted_markers([response(english[0])], planned["frFR"], REPO, TAG, "frFR"), set())

    def test_canonical_content_and_mentions_preserved_without_pinging(self):
        data = notes()
        planned = changelog.build_messages(data, REPO, TAG)
        self.assertEqual(planned[0]["embeds"][0]["description"], data["welcome"])
        self.assertEqual(planned[0]["embeds"][1]["title"], data["sections"][0]["title"])
        self.assertEqual(planned[0]["embeds"][1]["description"], "- " + data["sections"][0]["items"][0])
        self.assertEqual(planned, changelog.build_messages(copy.deepcopy(data), REPO, TAG))
        self.assertEqual(planned[0]["allowed_mentions"], {"parse": [], "users": [], "roles": [], "replied_user": False})
        self.assertTrue(planned[0]["enforce_nonce"])
        self.assertLessEqual(len(planned[0]["nonce"]), 25)

    def test_maximum_unicode_notes_split_only_at_whole_item_boundaries(self):
        data = notes()
        data["welcome"] = "😀" * 1200
        data["sections"] = [{"title": "Section " + str(i),
                             "items": [str(i) + ":" + str(j) + " " + "😀" * 790 for j in range(16)]}
                            for i in range(12)]
        data = changelog.parse_notes(json.dumps(data))
        planned = changelog.build_messages(data, REPO, TAG)
        self.assertGreater(len(planned), 1)
        descriptions = [embed["description"] for message in planned for embed in message["embeds"]]
        self.assertEqual(descriptions[0], data["welcome"])
        for section in data["sections"]:
            for item in section["items"]:
                self.assertEqual(sum(description.count("- " + item) for description in descriptions), 1)
        for message in planned:
            self.assertLessEqual(len(message["embeds"]), 10)
            self.assertLessEqual(sum(map(changelog.embed_length, message["embeds"])), 6000)
            self.assertEqual(sum("url" in embed for embed in message["embeds"]), 1)
            self.assertTrue(all(changelog.text_length(embed["description"]) <= 4096 for embed in message["embeds"]))
        self.assertEqual(len({message["nonce"] for message in planned}), len(planned))


class AccessTests(unittest.TestCase):
    def test_expected_bot_guild_name_type_and_permissions(self):
        for mutation in (lambda d: d.user.update(id="1554000000000000008"),
                         lambda d: d.user.update(bot=False),
                         lambda d: d.channel.update(guild_id="1554000000000000008"),
                         lambda d: d.channel.update(name="general"),
                         lambda d: d.channel.update(type=11),
                         lambda d: d.member.update(pending=True),
                         lambda d: d.member.update(communication_disabled_until="2999-01-01T00:00:00Z"),
                         lambda d: d.guild["roles"][0].update(permissions=str(changelog.REQUIRED_PERMISSIONS & ~changelog.READ_HISTORY))):
            api = Discord()
            mutation(api)
            with self.assertRaises(changelog.ChangelogError):
                changelog.verify_access(api, CHANNEL)
            self.assertFalse(api.posts)
        api = Discord()
        changelog.verify_access(api, CHANNEL)
        api.channel["type"] = 5
        changelog.verify_access(api, CHANNEL)

    def test_effective_overwrites_and_administrator_permissions(self):
        api = Discord()
        api.channel["permission_overwrites"] = [
            {"id": changelog.EXPECTED_GUILD_ID, "type": 0, "deny": str(changelog.SEND_MESSAGES), "allow": "0"},
            {"id": api.member["roles"][0], "type": 0, "deny": "0", "allow": str(changelog.SEND_MESSAGES)}]
        changelog.verify_access(api, CHANNEL)
        api.channel["permission_overwrites"].append(
            {"id": changelog.EXPECTED_BOT_ID, "type": 1, "deny": str(changelog.SEND_MESSAGES), "allow": "0"})
        with self.assertRaises(changelog.ChangelogError):
            changelog.verify_access(api, CHANNEL)
        api.guild["roles"][0]["permissions"] = str(1 << 3)
        changelog.verify_access(api, CHANNEL)
        api.guild["roles"] = []
        with self.assertRaises(changelog.ChangelogError):
            changelog.verify_access(api, CHANNEL)

    def test_history_bound_is_fail_closed_and_pagination_must_advance(self):
        api = Discord()
        payload = changelog.build_messages(notes(), REPO, TAG)[0]
        batch = [response(payload, identifier=str(1554000000000000000 - i)) for i in range(100)]
        api.history = batch
        with self.assertRaisesRegex(changelog.ChangelogError, "scan limit"):
            changelog.read_history(api, CHANNEL, max_pages=1)
        with self.assertRaisesRegex(changelog.ChangelogError, "did not advance"):
            changelog.read_history(api, CHANNEL, max_pages=2)
        with patch.object(api, "request", side_effect=[batch, []]) as request:
            self.assertEqual(len(changelog.read_history(api, CHANNEL, max_pages=2)), 100)
            self.assertIn("before=" + batch[-1]["id"], request.call_args.args[0])
        api.history = [dict(batch[0], channel_id="1554000000000000008")]
        with self.assertRaises(changelog.ChangelogError):
            changelog.read_history(api, CHANNEL)

    def test_check_access_is_read_only_and_does_not_need_release_or_github(self):
        api = Discord()
        with patch.object(changelog, "API", return_value=api), patch.dict(os.environ, {
                "DISCORD_BOT_TOKEN": "offline-token", "DISCORD_CHANGELOG_CHANNEL_ID": CHANNEL}), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(changelog.main(["--check-access", "--root", "/not/a/repository"]), 0)
        self.assertTrue(all(method == "GET" for _, method, _ in api.calls))
        self.assertTrue(any("/messages?" in path for path, _, _ in api.calls))


class PostingTests(unittest.TestCase):
    def setUp(self):
        self.api = Discord()
        data = notes()
        data["sections"][0]["items"] = [str(i) + " " + "x" * 790 for i in range(16)]
        self.planned = changelog.build_messages(data, REPO, TAG)
        self.assertGreater(len(self.planned), 1)

    def test_only_expected_bot_author_can_suppress_a_part(self):
        for author, webhook in (({"id": "1554000000000000009", "bot": True}, None),
                                ({"id": changelog.EXPECTED_BOT_ID, "bot": False}, None),
                                ({"id": changelog.EXPECTED_BOT_ID, "bot": True}, "1554000000000000009")):
            with self.subTest(author=author, webhook=webhook):
                history = [response(self.planned[0], author, webhook=webhook)]
                self.assertEqual(changelog.posted_markers(history, self.planned, REPO, TAG), set())
        own = response(self.planned[0])
        self.assertEqual(len(changelog.posted_markers([own], self.planned, REPO, TAG)), 1)

    def test_partial_retry_sends_only_missing_parts_with_stable_nonces(self):
        self.api.fail_part = 2
        with self.assertRaises(changelog.ChangelogError):
            changelog.post_missing(self.api, CHANNEL, self.planned, [], REPO, TAG)
        self.assertEqual(len(self.api.posts), 1)
        self.api.fail_part = None
        missing = changelog.post_missing(self.api, CHANNEL, self.planned, self.api.history, REPO, TAG)
        self.assertEqual(missing, len(self.planned) - 1)
        self.assertEqual(self.api.posts, self.planned)
        self.assertEqual(changelog.post_missing(self.api, CHANNEL, self.planned, self.api.history, REPO, TAG), 0)
        self.assertEqual(len(self.api.posts), len(self.planned))

    def test_conflicting_release_markers_fail_without_posting(self):
        changed = copy.deepcopy(self.planned[0])
        changed["embeds"][-1]["footer"]["text"] += " changed"
        with self.assertRaisesRegex(changelog.ChangelogError, "differ"):
            changelog.post_missing(self.api, CHANNEL, self.planned, [response(changed)], REPO, TAG)
        self.assertFalse(self.api.posts)

    def test_post_requires_confirmed_expected_author_and_part(self):
        with patch.object(self.api, "request", return_value=response(self.planned[0], {"id": "1554000000000000009", "bot": True})):
            with self.assertRaisesRegex(changelog.ChangelogError, "did not confirm"):
                changelog.post_missing(self.api, CHANNEL, self.planned, [], REPO, TAG)


class TransportTests(unittest.TestCase):
    def test_channel_creation_never_blindly_retries_ambiguous_server_failure(self):
        calls = []
        def fail(*args):
            calls.append(args)
            return 503, {}, b"ambiguous"
        api = changelog.API(changelog.DISCORD_API, "offline", transport=fail, sleep=lambda _: None)
        with self.assertRaisesRegex(changelog.ChangelogError, "unsafe retry"):
            api.request("/guilds/" + changelog.EXPECTED_GUILD_ID + "/channels", "POST", {"name": "test"})
        self.assertEqual(len(calls), 1)

    def test_429_and_5xx_use_bounded_retries(self):
        calls, delays = [], []
        replies = [(429, {}, b'{"retry_after":0.5}'), (502, {}, b"bad gateway"), (200, {}, b'{"ok":true}')]
        def fetch(method, url, headers, body):
            calls.append((method, url, headers, body))
            return replies.pop(0)
        api = changelog.API(changelog.DISCORD_API, "private-test-token", transport=fetch, sleep=delays.append)
        self.assertEqual(api.request("/example"), {"ok": True})
        self.assertEqual(delays, [0.5, 2])
        self.assertEqual(calls[0][2]["Authorization"], "Bot private-test-token")
        calls.clear()
        def fail(*args):
            calls.append(args)
            return 503, {}, b"failure"
        api.transport = fail
        with self.assertRaisesRegex(changelog.ChangelogError, "retry limit"):
            api.request("/example")
        self.assertEqual(len(calls), changelog.MAX_ATTEMPTS)

    def test_excessive_or_invalid_rate_limits_and_fatal_errors_do_not_retry_or_leak(self):
        for status, body in ((429, b'{"retry_after":9999}'), (429, b'{"retry_after":"NaN"}'),
                             (429, b'{}'), (401, b'{"error":"private-test-token"}'),
                             (302, b'{}')):
            delays = []
            api = changelog.API(changelog.DISCORD_API, "private-test-token",
                                transport=lambda *args: (status, {}, body), sleep=delays.append)
            with self.assertRaises(changelog.ChangelogError) as caught:
                api.request("/example")
            self.assertNotIn("private-test-token", str(caught.exception))
            self.assertFalse(delays)

    def test_ambiguous_post_retry_retains_exact_nonce_and_body(self):
        attempts = []
        def fetch(method, url, headers, body):
            attempts.append(body)
            if len(attempts) == 1:
                raise OSError("ambiguous disconnect")
            return 200, {}, b'{"ok":true}'
        api = changelog.API(changelog.DISCORD_API, "offline", transport=fetch, sleep=lambda _: None)
        payload = changelog.build_messages(notes(), REPO, TAG)[0]
        self.assertEqual(api.request("/example", "POST", payload), {"ok": True})
        self.assertEqual(attempts[0], attempts[1])
        attempts.clear()
        with self.assertRaisesRegex(changelog.ChangelogError, "unsafe retry"):
            api.request("/example", "POST", {})
        self.assertEqual(len(attempts), 1)

    def test_nonce_retries_stop_before_the_short_deduplication_window_expires(self):
        now, calls = [0], []
        def fetch(*args):
            calls.append(args)
            return 429, {}, b'{"retry_after":60}'
        def sleep(seconds):
            now[0] += seconds
        api = changelog.API(changelog.DISCORD_API, "offline", transport=fetch,
                            sleep=sleep, clock=lambda: now[0])
        with self.assertRaisesRegex(changelog.ChangelogError, "time window"):
            api.request("/example", "POST", changelog.build_messages(notes(), REPO, TAG)[0])
        self.assertEqual(len(calls), 2)
        self.assertEqual(now[0], 60)


class ArchiveTests(unittest.TestCase):
    def archive(self, *, lua=None, toc=None, duplicate=False, extra=None, localized=None):
        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            archive.writestr("QuestTogether/", b"")
            archive.writestr("QuestTogether/QuestTogether.toc", toc or "## Version: 1.2.4\nCore.lua\nReleaseNotes.lua\n")
            archive.writestr("QuestTogether/ReleaseNotes.lua", lua if lua is not None else changelog.render_lua(notes()))
            if localized is not None:
                archive.writestr("QuestTogether/LocalizedReleaseNotes.lua", localized)
            if duplicate:
                # A case/backslash alias is ambiguous for WoW's Windows clients.
                archive.writestr("questtogether\\releasenotes.lua", "other notes")
            if extra:
                archive.writestr(extra, b"other file")
        return output.getvalue()

    def verify(self, data):
        release = GitHub().release
        release["assets"][0]["size"] = len(data)
        changelog.verify_archive(release, REPO, TAG, notes(), download=lambda url, size: data)

    def test_published_zip_matches_baked_notes_and_toc(self):
        self.verify(self.archive())
        for data in (self.archive(lua=changelog.render_lua(notes(item="Outdated content for this version."))),
                     self.archive(toc="## Version: 1.2.3\nCore.lua\nReleaseNotes.lua\n"),
                     self.archive(toc="## Version: 1.2.4\nCore.lua\n")):
            with self.assertRaises((changelog.ChangelogError, changelog.NotesError)):
                self.verify(data)

    def test_localized_archive_requires_exact_data_and_native_load_order(self):
        expected = b"-- exact generated localized notes"
        toc = "## Version: 1.2.4\nCore.lua\nReleaseNotes.lua\nLocalizedReleaseNotes.lua\n"
        for candidate, valid in ((self.archive(toc=toc, localized=expected), True),
                                 (self.archive(toc=toc, localized=b"stale"), False),
                                 (self.archive(toc=toc), False),
                                 (self.archive(localized=expected), False),
                                 (self.archive(toc="## Version: 1.2.4\nCore.lua\nLocalizedReleaseNotes.lua\nReleaseNotes.lua\n", localized=expected), False)):
            release = GitHub().release
            release["assets"][0]["size"] = len(candidate)
            def verify():
                changelog.verify_archive(release, REPO, TAG, notes(), localized_lua=expected,
                                         download=lambda *args: candidate)
            if valid:
                verify()
            else:
                with self.assertRaises((changelog.ChangelogError, changelog.NotesError)):
                    verify()

    def test_archive_paths_contents_and_uncompressed_sizes_are_bounded(self):
        for data in (b"not a zip", self.archive(duplicate=True), self.archive(extra="QuestTogether/../other.lua"),
                     self.archive(lua="x" * (changelog.MAX_ARCHIVE_ENTRY_BYTES + 1))):
            with self.assertRaises(changelog.ChangelogError):
                self.verify(data)
        release = GitHub().release
        release["assets"][0]["size"] = changelog.MAX_ARCHIVE_BYTES + 1
        def reject_download(*args):
            raise AssertionError("must reject before downloading")
        with self.assertRaises(changelog.ChangelogError):
            changelog.verify_archive(release, REPO, TAG, notes(), download=reject_download)

    def test_public_download_has_no_credentials_and_rejects_untrusted_redirects(self):
        data = self.archive()
        request_headers = []
        class Response(io.BytesIO):
            code = 200
        class Opener:
            def open(self, request, timeout):
                request_headers.append(dict(request.header_items()))
                return Response(data)
        with patch.object(changelog.urllib.request, "build_opener", return_value=Opener()):
            self.assertEqual(changelog.download_archive(GitHub().release["assets"][0]["browser_download_url"], len(data)), data)
            with self.assertRaisesRegex(changelog.ChangelogError, "size differs"):
                changelog.download_archive(GitHub().release["assets"][0]["browser_download_url"], len(data) + 1)
        self.assertTrue(all("authorization" not in {key.lower() for key in headers} for headers in request_headers))
        redirect = changelog.PublicAssetRedirect()
        request = changelog.urllib.request.Request("https://github.com/example")
        for url in ("http://github.com/a", "https://example.invalid/a", "https://github.com@evil.invalid/a"):
            with self.assertRaises(changelog.ChangelogError):
                redirect.redirect_request(request, None, 302, "redirect", {}, url)
        accepted = redirect.redirect_request(request, None, 302, "redirect", {}, "https://release-assets.githubusercontent.com/example")
        self.assertFalse(accepted.has_header("Authorization"))


class WorkflowTests(unittest.TestCase):
    def test_exact_tag_checkout_and_concurrency_keep_different_releases_independent(self):
        workflow = (Path(__file__).resolve().parents[1] / ".github/workflows/discord-changelog.yml").read_text()
        self.assertIn("types: [published]", workflow)
        self.assertIn("default: true", workflow)
        self.assertIn("ref: refs/tags/${{ github.event.release.tag_name || inputs.tag }}", workflow)
        self.assertIn("group: discord-changelog-${{ github.repository }}-${{ github.event.release.tag_name || inputs.tag }}", workflow)
        self.assertIn("persist-credentials: false", workflow)
        self.assertIn("fetch-depth: 0", workflow)
        self.assertIn('scripts/discord_changelog.py --post --tag "$RELEASE_TAG"', workflow)
        self.assertEqual(workflow.count("--all-locales"), 2)


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="qt-localized-discord-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        write_translations(self.root, notes())

    def test_shared_validator_rejects_stale_source_structure_version_and_generated_lua(self):
        translated, expected = changelog.load_localized_notes(self.root, notes())
        self.assertEqual(set(translated), set(localization.LOCALES))
        self.assertEqual(expected, (self.root / changelog.LOCALIZED_LUA).read_bytes())
        path = self.root / "release_notes/frFR.json"
        original = json.loads(path.read_text())
        for mutate in (lambda w: w.update(source_sha256="a" * 64),
                       lambda w: w["notes"].update(version="1.2.3"),
                       lambda w: w["notes"]["sections"][0]["items"].append("Unexpected extra bullet.")):
            wrapper = copy.deepcopy(original)
            mutate(wrapper)
            path.write_text(json.dumps(wrapper))
            with self.assertRaises(ValueError):
                changelog.load_localized_notes(self.root, notes())
        path.write_text(json.dumps(original))
        (self.root / changelog.LOCALIZED_LUA).write_text("stale")
        with self.assertRaisesRegex(changelog.ChangelogError, "stale"):
            changelog.load_localized_notes(self.root, notes())

    def test_config_and_access_validate_each_locale_guild_bot_name_and_unique_id(self):
        config = locale_config()
        for mutate in (lambda c: c.update(guild_id="1554000000000000008"),
                       lambda c: c.update(bot_id="1554000000000000008"),
                       lambda c: c["channels"]["deDE"].update(name="general"),
                       lambda c: c["channels"]["deDE"].update(id=CHANNEL),
                       lambda c: c["channels"].update(xxXX=c["channels"]["esES"])):
            candidate = copy.deepcopy(config)
            mutate(candidate)
            (self.root / changelog.CHANNEL_CONFIG).write_text(json.dumps(candidate))
            with self.assertRaises(changelog.ChangelogError):
                changelog.load_channel_config(self.root)
        api = LocalizedDiscord()
        for locale, entry in config["channels"].items():
            changelog.verify_access(api, entry["id"], locale)
            if locale != "enUS":
                with self.assertRaises(changelog.ChangelogError):
                    changelog.verify_access(api, entry["id"])

    def test_provision_reuses_names_copies_category_permissions_and_is_idempotent(self):
        config = locale_config(configured=False)
        (self.root / changelog.CHANNEL_CONFIG).write_text(json.dumps(config))
        api = LocalizedDiscord(existing=False)
        api.channels[CHANNEL]["permission_overwrites"] = [
            {"id": changelog.EXPECTED_GUILD_ID, "type": 0, "allow": "0", "deny": str(1 << 5)}]
        with contextlib.redirect_stdout(io.StringIO()):
            selected = setup.provision(api, self.root)
            self.assertEqual(selected, {"enUS": CHANNEL})
            self.assertEqual(api.posts, [])
            selected = setup.provision(api, self.root, create=True)
            self.assertEqual(len(selected),len(changelog.LOCALE_CHANNEL_NAMES))
            self.assertEqual(len(api.posts),len(changelog.LOCALE_CHANNEL_NAMES) - 1)
            for payload in api.posts:
                self.assertEqual(payload["parent_id"], None)
                self.assertEqual(payload["permission_overwrites"], setup.overwrites(api.channels[CHANNEL]))
            self.assertEqual(setup.provision(api, self.root, create=True), selected)
            self.assertEqual(len(api.posts),len(changelog.LOCALE_CHANNEL_NAMES) - 1)
        self.assertEqual(changelog.load_channel_config(self.root), locale_config())

    def test_provision_fails_closed_for_missing_configured_or_conflicting_channels(self):
        api = LocalizedDiscord()
        identifier = api.config["channels"]["ruRU"]["id"]
        for mutation in (lambda: api.channels[identifier].update(name="renamed"),
                         lambda: api.channels[identifier].update(guild_id="1554000000000000008"),
                         lambda: api.channels[identifier].update(parent_id="1554000000000000008")):
            saved = copy.deepcopy(api.channels[identifier])
            mutation()
            with self.assertRaises(changelog.ChangelogError):
                setup.provision(api, self.root, create=True)
            self.assertEqual(api.posts, [])
            api.channels[identifier] = saved

    def test_provision_requires_manage_channels_and_never_changes_existing_permissions(self):
        (self.root / changelog.CHANNEL_CONFIG).write_text(json.dumps(locale_config(configured=False)))
        api = LocalizedDiscord(existing=False)
        api.guild["roles"][0]["permissions"] = str(changelog.REQUIRED_PERMISSIONS)
        before = (self.root / changelog.CHANNEL_CONFIG).read_bytes()
        with self.assertRaisesRegex(changelog.ChangelogError, "Manage Channels"):
            setup.provision(api, self.root, create=True)
        self.assertFalse(api.posts)
        self.assertEqual((self.root / changelog.CHANNEL_CONFIG).read_bytes(), before)
        self.assertTrue(all(method == "GET" for _, method, _ in api.calls))

    def test_partial_channel_creation_is_rediscovered_without_duplicate_creation(self):
        config = locale_config(configured=False)
        path = self.root / changelog.CHANNEL_CONFIG
        path.write_text(json.dumps(config))
        before = path.read_bytes()
        api = LocalizedDiscord(existing=False)
        original = api.request
        def ambiguous(path, method="GET", payload=None):
            result = original(path, method, payload)
            if method == "POST":
                raise changelog.ChangelogError("ambiguous response after channel was created")
            return result
        with patch.object(api, "request", side_effect=ambiguous), contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(changelog.ChangelogError):
                setup.provision(api, self.root, create=True)
        self.assertEqual(len(api.posts), 1)
        self.assertEqual(path.read_bytes(), before)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(len(setup.provision(api, self.root, create=True)),len(changelog.LOCALE_CHANNEL_NAMES))
        self.assertEqual(len(api.posts),len(changelog.LOCALE_CHANNEL_NAMES) - 1)
        self.assertEqual(len({payload["name"] for payload in api.posts}),len(changelog.LOCALE_CHANNEL_NAMES) - 1)

    def test_duplicate_existing_locale_names_are_rejected_before_creation(self):
        api = LocalizedDiscord()
        identifier = api.config["channels"]["deDE"]["id"]
        api.channels["1557000000000000000"] = dict(api.channels[identifier], id="1557000000000000000")
        with self.assertRaisesRegex(changelog.ChangelogError, "ambiguous"):
            setup.provision(api, self.root, create=True)
        self.assertFalse(api.posts)

    def test_optional_token_file_reads_only_named_entry_without_evaluation(self):
        path = self.root / "private.env"
        path.write_text('UNRELATED_SECRET=do-not-use\nDISCORD_BOT_TOKEN="offline.token-value"\n')
        with patch.dict(os.environ, {}, clear=True):
            self.assertEqual(setup.bot_token(path), "offline.token-value")
            path.write_text('DISCORD_BOT_TOKEN=$(touch sentinel)\n')
            with self.assertRaises(changelog.ChangelogError) as error:
                setup.bot_token(path)
            self.assertNotIn("touch", str(error.exception))
            self.assertFalse((self.root / "sentinel").exists())


class ReleaseTests(unittest.TestCase):
    def test_public_published_asset_and_exact_successful_workflow_are_required(self):
        changelog.verify_release(GitHub(), REPO, TAG, SHA)
        cases = [lambda g: g.repo.update(private=True), lambda g: g.ref["object"].update(sha="c" * 40),
                 lambda g: g.release.update(draft=True), lambda g: g.release.update(published_at=None),
                 lambda g: g.release.update(html_url="https://example.invalid/release"),
                 lambda g: g.release.update(assets=[]), lambda g: g.release["assets"][0].update(state="new"),
                 lambda g: g.release["assets"][0].update(name="QuestTogether-v0.0.1.zip"),
                 lambda g: g.release["assets"][0].update(size=0), lambda g: g.runs[0].update(head_sha="c" * 40),
                 lambda g: g.runs[0].update(event="pull_request"), lambda g: g.runs[0].update(path="other.yml"),
                 lambda g: g.runs[0].update(status="queued"), lambda g: g.runs[0].update(conclusion="failure")]
        for mutation in cases:
            api = GitHub()
            mutation(api)
            with self.assertRaises(changelog.ChangelogError):
                changelog.verify_release(api, REPO, TAG, SHA)

    def test_annotated_tags_and_newer_failed_run_do_not_reuse_old_success(self):
        api = GitHub()
        api.ref["object"] = {"sha": "b" * 40, "type": "tag"}
        changelog.verify_release(api, REPO, TAG, SHA)
        api.runs.append(dict(api.runs[0], id=2, conclusion="failure"))
        with self.assertRaisesRegex(changelog.ChangelogError, "did not succeed"):
            changelog.verify_release(api, REPO, TAG, SHA)

    def test_readiness_wait_is_bounded_and_can_recover(self):
        now, sleeps = [0], []
        def sleep(seconds):
            sleeps.append(seconds)
            now[0] += seconds
        with patch.object(changelog, "verify_release", side_effect=changelog.ReleaseNotReady("waiting")) as check:
            with self.assertRaises(changelog.ReleaseNotReady):
                changelog.wait_for_release(None, REPO, TAG, SHA, 20, clock=lambda: now[0], sleep=sleep)
            self.assertEqual(now[0], 20)
            self.assertEqual(check.call_count, 3)
        with patch.object(changelog, "verify_release", side_effect=[changelog.ReleaseNotReady("waiting"), {"ok": True}]):
            self.assertEqual(changelog.wait_for_release(None, REPO, TAG, SHA, 20, clock=lambda: now[0], sleep=sleep), {"ok": True})


class LocalNotesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="questtogether-discord-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        self.environment.update({"GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": os.devnull,
                                 "GIT_AUTHOR_NAME": "Offline test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
                                 "GIT_COMMITTER_NAME": "Offline test", "GIT_COMMITTER_EMAIL": "test@example.invalid"})
        self.patch_env = patch.dict(os.environ, self.environment, clear=True)
        self.patch_env.start()
        self.addCleanup(self.patch_env.stop)
        self.git("init", "-q")
        self.git("config", "core.hooksPath", os.devnull)
        self.commit_notes(notes("1.2.3", "An older quest-sharing improvement."))
        self.commit_notes(notes())
        self.sha = self.git("rev-parse", "HEAD")

    def git(self, *args):
        result = subprocess.run(["git", "-c", "commit.gpgsign=false", "-C", str(self.root), *args],
                                capture_output=True, text=True, check=True)
        return result.stdout.strip()

    def write_notes(self, data):
        (self.root / "QuestTogether.toc").write_text("## Version: " + data["version"] + "\nCore.lua\nReleaseNotes.lua\n")
        (self.root / "release_notes.json").write_text(json.dumps(data), encoding="utf-8")
        (self.root / "ReleaseNotes.lua").write_text(changelog.render_lua(data), encoding="utf-8")

    def commit_notes(self, data):
        self.write_notes(data)
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture notes " + data["version"])
        self.git("tag", "-a", "v" + data["version"], "-m", "Fixture release")

    def prepare_localized_release(self):
        write_translations(self.root, notes())
        with (self.root / "QuestTogether.toc").open("a") as handle:
            handle.write("LocalizedReleaseNotes.lua\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Fixture localized release")
        self.git("tag", "-fa", TAG, "-m", "Fixture localized release")
        self.sha = self.git("rev-parse", "HEAD")

    def test_all_locales_preflight_every_target_before_posting_and_retries_missing_channels(self):
        self.prepare_localized_release()
        github, discord = GitHub(self.sha), LocalizedDiscord()
        def api(base, token):
            return github if base == changelog.GITHUB_API else discord
        last = locale_config()["channels"]["ruRU"]["id"]
        discord.channels[last]["name"] = "wrong-destination"
        args = ["--post", "--all-locales", "--tag", TAG, "--root", str(self.root)]
        with patch.object(changelog, "API", side_effect=api), patch.object(changelog, "verify_archive") as archive, \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(changelog.main(args), 1)
            self.assertFalse(discord.posts)
            discord.channels[last]["name"] = changelog.LOCALE_CHANNEL_NAMES["ruRU"]
            discord.fail_part = 3
            self.assertEqual(changelog.main(args), 1)
            self.assertEqual(len(discord.posts), 2)
            discord.fail_part = None
            self.assertEqual(changelog.main(args), 0)
            self.assertEqual(len(discord.posts),len(changelog.LOCALE_CHANNEL_NAMES))
            self.assertEqual(changelog.main(args), 0)
            self.assertEqual(len(discord.posts),len(changelog.LOCALE_CHANNEL_NAMES))
            self.assertEqual(archive.call_args.kwargs["localized_lua"],
                             (self.root / changelog.LOCALIZED_LUA).read_bytes())
        self.assertEqual(len({payload["nonce"] for payload in discord.posts}),len(changelog.LOCALE_CHANNEL_NAMES))
        for locale, entry in locale_config()["channels"].items():
            message = discord.histories[entry["id"]][0]
            self.assertIn(changelog.release_key(REPO, TAG, locale), message["embeds"][-1]["footer"]["text"])

    def test_stale_localized_zip_and_late_conflicting_history_prevent_all_posts(self):
        self.prepare_localized_release()
        github, discord = GitHub(self.sha), LocalizedDiscord()
        def api(base, token):
            return github if base == changelog.GITHUB_API else discord
        args = ["--post", "--all-locales", "--tag", TAG, "--root", str(self.root)]
        with patch.object(changelog, "API", side_effect=api), patch.object(changelog, "verify_archive", \
                side_effect=changelog.ChangelogError("stale localized archive")), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(changelog.main(args), 1)
        self.assertFalse(discord.calls)
        translated, _ = changelog.load_localized_notes(self.root, notes())
        message = response(changelog.build_messages(translated["ruRU"], REPO, TAG, "ruRU")[0])
        last = locale_config()["channels"]["ruRU"]["id"]
        message["channel_id"] = last
        message["embeds"][-1]["footer"]["text"] += " conflict"
        discord.histories[last].append(message)
        with patch.object(changelog, "API", side_effect=api), patch.object(changelog, "verify_archive"), \
                contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(changelog.main(args), 1)
        self.assertFalse(discord.posts)

    def test_current_backfill_requires_exact_published_source_and_checks_all_destinations(self):
        source = notes("5.13.1")
        self.write_notes(source)
        write_translations(self.root, source)
        discord = LocalizedDiscord()
        translated, _ = changelog.load_localized_notes(self.root, source)
        last = locale_config()["channels"]["ruRU"]["id"]
        discord.channels[last]["name"] = "wrong-destination"
        with patch.object(changelog, "load_notes", return_value=(source, SHA)) as load, \
                patch.object(changelog, "verify_release", return_value={}) as release, \
                patch.object(changelog, "verify_archive") as archive, contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(changelog.ChangelogError):
                setup.post_current(self.root, self.root, discord, object())
            self.assertFalse(discord.posts)
            discord.channels[last]["name"] = changelog.LOCALE_CHANNEL_NAMES["ruRU"]
            setup.post_current(self.root, self.root, discord, object())
            setup.post_current(self.root, self.root, discord, object())
            self.assertEqual(len(discord.posts),len(changelog.LOCALE_CHANNEL_NAMES) - 1)
            self.assertEqual(load.call_args.args[1], "v5.13.1")
            self.assertEqual(load.call_args.kwargs, {"exact": True})
            self.assertEqual(release.call_args.args[2:], ("v5.13.1", SHA))
            self.assertNotIn("localized_lua", archive.call_args.kwargs)
            self.write_notes(notes("5.13.2", "Unpublished future feature."))
            with self.assertRaisesRegex(changelog.ChangelogError, "published 5.13.1"):
                setup.post_current(self.root, self.root, discord, object())
            self.assertEqual(len(discord.posts),len(changelog.LOCALE_CHANNEL_NAMES) - 1)

    def test_exact_tag_generation_and_history_validation(self):
        data, sha = changelog.load_notes(self.root, TAG, exact=True)
        self.assertEqual(sha, self.sha)
        self.assertEqual(data, notes())
        with self.assertRaises(changelog.ChangelogError):
            changelog.load_notes(self.root, "v1.2.3", exact=True)
        self.write_notes(notes(item="New uncommitted release content."))
        with self.assertRaisesRegex(changelog.ChangelogError, "clean checkout"):
            changelog.load_notes(self.root, TAG, exact=True)
        (self.root / "ReleaseNotes.lua").write_text("stale")
        with self.assertRaisesRegex(changelog.ChangelogError, "stale"):
            changelog.load_notes(self.root)

    def test_version_only_notes_are_not_fresh_release_content(self):
        self.write_notes(notes(item="An older quest-sharing improvement."))
        with self.assertRaisesRegex(changelog.NotesError, "unchanged"):
            changelog.load_notes(self.root)

    def test_dry_run_never_reads_credentials_or_calls_apis(self):
        output = io.StringIO()
        with patch.object(changelog, "API", side_effect=AssertionError("dry run attempted API")), contextlib.redirect_stdout(output):
            self.assertEqual(changelog.main(["--root", str(self.root)]), 0)
        self.assertEqual(json.loads(output.getvalue()), changelog.build_messages(notes(), REPO, TAG))

    def test_post_orchestration_rechecks_release_access_and_history_on_retry(self):
        github, discord = GitHub(self.sha), Discord()
        def api(base, token):
            return github if base == changelog.GITHUB_API else discord
        with patch.object(changelog, "API", side_effect=api), patch.object(changelog, "verify_archive") as artifact, patch.dict(os.environ, {
                "GH_TOKEN": "offline", "DISCORD_BOT_TOKEN": "offline", "DISCORD_CHANGELOG_CHANNEL_ID": CHANNEL}), contextlib.redirect_stdout(io.StringIO()):
            for _ in range(2):
                self.assertEqual(changelog.main(["--post", "--tag", TAG, "--root", str(self.root)]), 0)
        self.assertEqual(len(discord.posts), 1)
        self.assertEqual(sum(path == "/users/@me" for path, _, _ in discord.calls), 2)
        self.assertEqual(artifact.call_count, 2)

    def test_unpublished_or_failed_release_never_reaches_discord(self):
        github = GitHub(self.sha)
        github.release["draft"] = True
        def api(base, token):
            self.assertEqual(base, changelog.GITHUB_API)
            return github
        with patch.object(changelog, "API", side_effect=api), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(changelog.main(["--post", "--tag", TAG, "--root", str(self.root)]), 1)

    def test_stale_published_zip_never_reaches_discord(self):
        github = GitHub(self.sha)
        def api(base, token):
            self.assertEqual(base, changelog.GITHUB_API)
            return github
        with patch.object(changelog, "API", side_effect=api), patch.object(changelog, "verify_archive", side_effect=changelog.ChangelogError("stale ZIP notes")), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(changelog.main(["--post", "--tag", TAG, "--root", str(self.root)]), 1)


if __name__ == "__main__":
    unittest.main()
