#!/usr/bin/env python3
"""Offline safeguards for the shared factual-brief boundary."""
import json
import unittest

import release_note_facts as F


def source():
    return {
        'version': '8.0.0',
        'welcome': 'Welcome! VIP is available for your characters.',
        'sections': [{
            'title': 'Your VIP cosmetics',
            'items': ['After a grant, use /qt claim. The fill is 25%, capped at 75%.',
                      'Instructions: https://example.org/guide'],
            'illustration': 'vip-cosmetics',
            'tip': {'label': 'Tip:', 'text': 'Use /qt vip to see instructions.'},
        }],
    }


def draft():
    return {
        'welcome': 'VIP access across characters.',
        'sections': [{
            'title': 'VIP activation and appearance',
            'items': ['Prerequisite: existing VIP grant; activation command: /qt claim.',
                      'Fill opacity: 25%; maximum: 75%.',
                      'Instructions URL: https://example.org/guide'],
            'tip': {'label': 'Tip:', 'text': 'Instructions command: /qt vip.'},
        }],
    }


class FactsTests(unittest.TestCase):
    def test_context_boundary_removes_published_prose_but_keeps_code_and_commits(self):
        evidence = '\n'.join([
            'Current addon version: 8.0.0',
            'PREVIOUS NOTES (do not repeat unchanged features):',
            '{"welcome":"OLD FINAL ENGLISH"}',
            'COMMIT EVIDENCE:', 'Implement VIP claim validation',
            'BEGIN UNTRUSTED SOURCE CHANGELOG.md',
            '+FINAL ENGLISH COPY', 'END UNTRUSTED SOURCE',
            'BEGIN UNTRUSTED SOURCE VIPIdentity.lua',
            '+requireGrantedVIP()', 'END UNTRUSTED SOURCE',
        ])
        result = F.writer_evidence(evidence)
        self.assertNotIn('OLD FINAL ENGLISH', result)
        self.assertNotIn('FINAL ENGLISH COPY', result)
        self.assertIn('Implement VIP claim validation', result)
        self.assertIn('+requireGrantedVIP()', result)
        self.assertIn('Current addon version: 8.0.0', result)

    def test_shortened_prose_blocks_fail_closed_without_discarding_later_code(self):
        evidence = ('BEGIN UNTRUSTED SOURCE CHANGELOG.md\nprose without closing marker\n'
                    'BEGIN UNTRUSTED SOURCE Core.lua\n+code()\nEND UNTRUSTED SOURCE')
        self.assertNotIn('prose', F.writer_evidence(evidence))
        self.assertIn('+code()', F.writer_evidence(evidence))
        self.assertEqual(F.writer_evidence('PREVIOUS NOTES (old):\ntruncated prose'), '')
        self.assertEqual(F.writer_evidence('BEGIN UNTRUSTED SOURCE CHANGELOG.md\ntruncated prose'), '')

    def test_separate_coverage_pass_receives_facts_and_preserves_assets_without_writing(self):
        calls = []
        def provider(payload, key, model, **kwargs):
            calls.append((json.loads(payload), kwargs['instructions']))
            return draft()
        result = F.prepare_brief(source(), 'Actual code evidence', None, generator=provider)
        self.assertEqual(len(calls), 2)
        self.assertNotIn('candidate_facts', calls[0][0])
        self.assertEqual(calls[1][0]['candidate_facts'], result)
        self.assertIn('independent coverage editor', calls[1][1])
        self.assertEqual(result['sections'][0]['illustration'], 'vip-cosmetics')
        self.assertEqual(len(result['sections'][0]['items']), 3)
        self.assertEqual(result['version'], source()['version'])
        self.assertEqual(calls[0][0]['approved_release_scope'], source())
        self.assertEqual(calls[0][0]['protected_tokens'], {
            'commands': ['/qt claim', '/qt vip'],
            'links': ['https://example.org/guide'], 'numeric_values': ['25', '75'],
        })
        self.assertEqual(calls[0][0]['protected_tokens'], calls[1][0]['protected_tokens'])
        self.assertIn('Keep word-written quantities as words', calls[0][1])
        for _, instructions in calls:
            self.assertIn('strict inclusion boundary', instructions)
            self.assertIn('Do not add cache states', instructions)
        self.assertIn('Remove facts supported only by source code', calls[1][1])

    def test_word_counts_and_unspecified_commands_are_not_expanded_from_code(self):
        approved = {
            'version': '5.8.2', 'welcome': 'Fix two false failures in the settings command.',
            'sections': [{'title': 'Validation', 'items': ['Six client profiles; 333 passing tests.']}],
        }
        self.assertEqual(F.protected_tokens(approved), {
            'commands': [], 'links': [], 'numeric_values': ['333'],
        })
        bad = {'welcome': 'Fix two false failures in /qt options.',
               'sections': [{'title': 'Validation', 'items': ['Six client profiles; 333 passing tests.']}]}
        with self.assertRaisesRegex(ValueError, "unsupported=.*qt options"):
            F.prepare_brief(approved, 'Code uses /qt options for settings.', None,
                            generator=lambda *a, **k: bad)

    def test_omitted_or_invented_commands_links_numbers_and_tips_are_rejected(self):
        candidates = []
        for old, new in [('/qt claim', '/qt help'), ('25%', '50%'),
                         ('https://example.org/guide', 'https://example.org/elsewhere')]:
            candidates.append(json.loads(json.dumps(draft()).replace(old, new)))
        no_tip = draft(); del no_tip['sections'][0]['tip']; candidates.append(no_tip)
        fewer = draft(); fewer['sections'] = []; candidates.append(fewer)
        extra = draft(); extra['sections'][0]['items'].append('Retry 3 times.'); candidates.append(extra)
        for bad in candidates:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                F.prepare_brief(source(), 'Actual evidence', None, generator=lambda *a, **k: bad)

    def test_editor_cannot_remove_a_constraint_token_and_cached_versions_must_match(self):
        def provider(payload, *args, **kwargs):
            result = draft()
            if 'candidate_facts' in json.loads(payload):
                result['sections'][0]['items'][1] = 'Fill opacity: 25%.'
            return result
        with self.assertRaisesRegex(ValueError, 'numeric values'):
            F.prepare_brief(source(), 'Actual evidence', None, generator=provider)
        brief = F.prepare_brief(source(), 'Actual evidence', None, generator=lambda *a, **k: draft())
        brief['version'] = '8.0.1'
        with self.assertRaisesRegex(ValueError, 'version/section'):
            F.validate_brief(source(), brief)

    def test_silent_release_needs_no_provider_and_missing_evidence_is_rejected(self):
        silent = {'version': '8.0.0', 'welcome': '', 'sections': []}
        def forbidden(*args, **kwargs):
            self.fail('silent release must not call provider')
        self.assertEqual(F.prepare_brief(silent, 'Evidence', None, generator=forbidden), silent)
        for evidence in ['', None, 'PREVIOUS NOTES (old):\nOnly old prose']:
            with self.subTest(evidence=evidence), self.assertRaises(ValueError):
                F.prepare_brief(source(), evidence, None, generator=forbidden)


if __name__ == '__main__':
    unittest.main()
