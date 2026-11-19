#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Build two client-scoped files and submit them once; never poll processing.

API contract: https://support.curseforge.com/support/solutions/articles/9000197321
"""
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import uuid
import zipfile

import package

PROJECT = 296929
API = "https://wow.curseforge.com/api"
LABELS = {"forever": "Forever", "retail-classic": "Retail & Classic"}


class UploadError(ValueError):
    pass


def token(environment=None):
    environment = os.environ if environment is None else environment
    value = environment.get("CURSEFORGE_API_TOKEN", "").strip()
    if not value:
        config = Path(environment.get("XDG_CONFIG_HOME") or Path.home() / ".config")
        path = config / "QuestTogether/curseforge-token"
        try:
            info = path.lstat()
            if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
                raise UploadError("CurseForge token file must be a private regular file (chmod 600)")
            value = path.read_text().strip()
        except FileNotFoundError:
            pass
    if not value:
        raise UploadError("set CURSEFORGE_API_TOKEN or configure ~/.config/QuestTogether/curseforge-token")
    if "\n" in value or "\r" in value:
        raise UploadError("invalid CurseForge token")
    return value


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Client:
    def __init__(self, credential):
        self.credential = credential
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, path, body=None, content_type=None):
        headers = {"X-Api-Token": self.credential, "Accept": "application/json"}
        if content_type:
            headers["Content-Type"] = content_type
        request = urllib.request.Request(API + path, data=body, headers=headers)
        try:
            with self.opener.open(request, timeout=120 if body is not None else 30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            # Keep the status actionable without exposing URLs, credentials or
            # arbitrary server response text in unattended deployment logs.
            raise UploadError("CurseForge request failed (HTTP " + str(error.code)
                              + "); credentials and response body omitted") from None
        except (OSError, ValueError, urllib.error.URLError):
            # Response bodies and exception URLs can contain authentication data.
            raise UploadError("CurseForge request failed; credentials and response body omitted") from None

    def versions(self):
        return self.request("/game/versions")

    def upload(self, archive, metadata):
        boundary = "qt" + uuid.uuid4().hex
        prefix = ("--" + boundary + '\r\nContent-Disposition: form-data; name="metadata"\r\n'
                  "Content-Type: application/json\r\n\r\n" + json.dumps(metadata) + "\r\n--" + boundary
                  + '\r\nContent-Disposition: form-data; name="file"; filename="' + archive.name
                  + '"\r\nContent-Type: application/zip\r\n\r\n').encode()
        body = prefix + archive.read_bytes() + ("\r\n--" + boundary + "--\r\n").encode()
        return self.request("/projects/" + str(PROJECT) + "/upload-file", body,
                            "multipart/form-data; boundary=" + boundary)


def check_webhook_disabled(github, repository):
    hooks = github.request("/repos/" + repository + "/hooks?per_page=100")
    if not isinstance(hooks, list) or len(hooks) >= 100:
        raise UploadError("cannot establish CurseForge webhook state")
    for hook in hooks:
        url = urllib.parse.urlsplit(hook.get("config", {}).get("url", ""))
        if hook.get("active") and url.hostname in {"www.curseforge.com", "wow.curseforge.com", "curseforge.com"} \
                and url.path.rstrip("/") == "/api/projects/" + str(PROJECT) + "/package":
            raise UploadError("disable the old CurseForge package webhook before publishing split files")


def prepare(root, tag, commit, output):
    files = []
    for flavor in package.FLAVORS:
        archive = output / ("QuestTogether-" + tag + "-" + flavor + ".zip")
        version, _, digest = package.package(root, archive, commit, flavor)
        if tag != "v" + version:
            raise UploadError("CurseForge package version differs from the release tag")
        with zipfile.ZipFile(archive) as bundle:
            toc = bundle.read("QuestTogether/QuestTogether.toc").decode()
        interfaces = re.findall(r"^## Interface: ([^\r\n]+)$", toc, re.M)
        if len(interfaces) != 1:
            raise UploadError("missing distribution interfaces")
        files.append({"flavor": flavor, "archive": archive, "sha256": digest,
                      "interfaces": [value.strip() for value in interfaces[0].split(",")]})
    return files


def metadata(file, tag, changelog, versions):
    ids = []
    for interface in file["interfaces"]:
        matches = [entry["id"] for entry in versions if str(entry.get("apiVersion")) == interface]
        if len(matches) != 1 or type(matches[0]) is not int:
            raise UploadError("CurseForge has no unique game version for interface " + interface)
        ids.append(matches[0])
    return {"displayName": "QuestTogether " + tag[1:] + " (" + LABELS[file["flavor"]] + ")",
            "changelog": changelog, "changelogType": "markdown", "gameVersions": ids,
            "releaseType": "beta" if "-beta." in tag else "alpha" if "-alpha." in tag else "release",
            "relations": {"projects": ([{"slug": "questiedb", "projectID": 1696795,
                                         "type": "requiredDependency"}] if file["flavor"] == "forever" else [])}}


def save(path, value):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as stream:
        pending = Path(stream.name)
        json.dump(value, stream, sort_keys=True)
        stream.write("\n")
        stream.flush()
        os.fsync(stream.fileno())
    try:
        pending.replace(path)
    finally:
        pending.unlink(missing_ok=True)


def publish(files, tag, commit, changelog, output, client, versions=None):
    versions = client.versions() if versions is None else versions
    if not isinstance(versions, list):
        raise UploadError("invalid CurseForge game-version response")
    # Resolve both sets before submitting either file.
    prepared = [(file, metadata(file, tag, changelog, versions)) for file in files]
    for file, values in prepared:
        if hashlib.sha256(file["archive"].read_bytes()).hexdigest() != file["sha256"]:
            raise UploadError("CurseForge archive changed after packaging")
        receipt = output / ("curseforge-" + file["flavor"] + ".json")
        identity = {"project": PROJECT, "commit": commit, "tag": tag, "sha256": file["sha256"],
                    "metadata": values}
        if receipt.exists():
            old = json.loads(receipt.read_text())
            if old.get("identity") != identity:
                raise UploadError("CurseForge submission receipt differs from this candidate")
            if old.get("status") == "submitted" and type(old.get("fileID")) is int and old["fileID"] > 0:
                print("CurseForge " + LABELS[file["flavor"]] + " already submitted; skipping.", flush=True)
                continue
            raise UploadError("CurseForge upload outcome is unknown for " + file["flavor"]
                              + "; reconcile its local receipt before resuming to avoid duplicate files")
        # The API has no idempotency key. Never automatically retry an uncertain POST.
        save(receipt, {"identity": identity, "status": "submitting"})
        result = client.upload(file["archive"], values)
        if not isinstance(result, dict) or type(result.get("id")) is not int or result["id"] <= 0:
            raise UploadError("CurseForge returned no valid file ID; upload outcome is unknown")
        save(receipt, {"identity": identity, "status": "submitted", "fileID": result["id"]})
        print("Submitted CurseForge " + LABELS[file["flavor"]] + " file " + str(result["id"])
              + "; review is not monitored.", flush=True)
