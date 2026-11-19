#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Offline CurseForge contract tests; no service calls or real credentials."""
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import urllib.error

import curseforge_upload as cf


class UploadTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.files = []
        for flavor, interface in (("forever", "16001"), ("retail-classic", "120001")):
            path = self.root / (flavor + ".zip")
            path.write_bytes(flavor.encode())
            self.files.append(dict(flavor=flavor, archive=path, sha256=hashlib.sha256(path.read_bytes()).hexdigest(), interfaces=[interface]))
        self.submitted = []
        self.fail = None

    def versions(self):
        return [{"apiVersion": "16001", "id": 10}, {"apiVersion": "120001", "id": 20}]

    def upload(self, archive, metadata):
        if archive.stem == self.fail:
            raise cf.UploadError("simulated connection loss")
        self.submitted.append((archive.name, metadata))
        return {"id": 40 + len(self.submitted)}

    def publish(self, **changes):
        values = dict(files=self.files, tag="v10.1.1", commit="a" * 40, changelog="Notes", output=self.root, client=self)
        values.update(changes)
        cf.publish(**values)

    def test_only_forever_declares_required_questiedb_and_versions_do_not_overlap(self):
        self.publish()
        first, second = [values for _, values in self.submitted]
        self.assertEqual(first['gameVersions'], [10])
        self.assertEqual(second['gameVersions'], [20])
        self.assertEqual(first['relations']['projects'], [{'slug':'questiedb', 'projectID':1696795, 'type':'requiredDependency'}])
        self.assertNotIn('relations', second)
        self.publish()
        self.assertEqual(len(self.submitted), 2)

    def test_missing_or_ambiguous_versions_fail_before_any_submission(self):
        for rows in ([], self.versions() + [self.versions()[0]]):
            with patch.object(self, 'versions', return_value=rows), self.assertRaises(cf.UploadError):
                self.publish()
        self.assertEqual(self.submitted, [])

    def test_beta_alpha_stable_types(self):
        for tag, release_type in [('v1.2.3','release'),('v1.2.3-beta.1','beta'),('v1.2.3-alpha.1','alpha')]:
            self.assertEqual(cf.metadata(self.files[0],tag,'Notes',self.versions())['releaseType'],release_type)

    def test_partial_failure_never_resends_successful_or_uncertain_uploads(self):
        self.fail = 'retail-classic'
        with self.assertRaises(cf.UploadError): self.publish()
        self.fail = None
        with self.assertRaisesRegex(cf.UploadError, 'outcome is unknown'): self.publish()
        self.assertEqual(len(self.submitted),1)
        receipt = json.loads((self.root/'curseforge-forever.json').read_text())
        self.assertEqual(receipt['status'],'submitted')
        self.assertEqual(receipt['fileID'],41)

    def test_changed_payload_or_receipt_is_not_silently_reused(self):
        self.publish()
        with self.assertRaisesRegex(cf.UploadError,'differs'): self.publish(commit='b'*40)
        self.files[0]['archive'].write_bytes(b'changed')
        with self.assertRaisesRegex(cf.UploadError,'changed'): self.publish()
        self.assertEqual(len(self.submitted),2)

    def test_token_file_permissions_and_environment_override(self):
        directory=self.root/'QuestTogether';directory.mkdir()
        path=directory/'curseforge-token';path.write_text('private-fixture-token\n');path.chmod(0o600)
        env={'XDG_CONFIG_HOME':str(self.root)}
        self.assertEqual(cf.token(env),'private-fixture-token')
        path.chmod(0o644)
        with self.assertRaises(cf.UploadError):cf.token(env)
        self.assertEqual(cf.token({'CURSEFORGE_API_TOKEN':'env-fixture-token'}),'env-fixture-token')

    def test_webhook_guard_ignores_unrelated_hooks_and_requires_retirement(self):
        class Github:
            def request(_, path):return hooks
        hooks=[{'active':True,'config':{'url':'https://example.invalid/hook'}}]
        cf.check_webhook_disabled(Github(),'owner/repo')
        hooks.append({'active':True,'config':{'url':'https://www.curseforge.com/api/projects/296929/package?token=private'}})
        with self.assertRaises(cf.UploadError):cf.check_webhook_disabled(Github(),'owner/repo')
        hooks[-1]['active']=False
        cf.check_webhook_disabled(Github(),'owner/repo')

    def test_upload_uses_authenticated_post_with_metadata_and_file_and_redacts_failures(self):
        client=cf.Client('private-fixture-token')
        captured=[]
        def request(req, timeout):
            captured.append(req)
            self.assertEqual(timeout,120)
            return io.BytesIO(b'{"id": 123}')
        with patch.object(client.opener,'open',side_effect=request):
            self.assertEqual(client.upload(self.files[0]['archive'],{'relations':{'projects':[]}}),{'id':123})
        req=captured[0]
        self.assertEqual(req.full_url,'https://wow.curseforge.com/api/projects/296929/upload-file')
        self.assertEqual(req.get_header('X-api-token'),'private-fixture-token')
        self.assertIn(b'name="metadata"',req.data)
        self.assertIn(b'name="file"',req.data)
        self.assertIn(b'forever',req.data)
        with patch.object(client.opener,'open',side_effect=OSError('private-fixture-token')):
            with self.assertRaises(cf.UploadError) as failure:client.versions()
        self.assertNotIn('private-fixture-token',str(failure.exception))
        with patch.object(client.opener,'open',side_effect=urllib.error.HTTPError(
                'https://example.invalid/private-fixture-token',400,'private-fixture-token',{},None)):
            with self.assertRaisesRegex(cf.UploadError, 'HTTP 400') as failure:client.versions()
        self.assertNotIn('private-fixture-token',str(failure.exception))
        self.assertIsNone(cf.NoRedirect().redirect_request(None,None,302,'',{},'https://elsewhere.invalid'))


if __name__=='__main__':unittest.main()
