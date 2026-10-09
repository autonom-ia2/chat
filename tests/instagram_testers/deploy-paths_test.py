"""Release routing: VPS-only updates must not rebuild the AWS application."""
import fnmatch
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
WORKFLOWS = ('deploy-autonomia-blue-green.yml', 'deploy-hub2you-blue-green.yml')
VPS_ONLY = (
    'scripts/instagram_testers/session-manager.mjs',
    'scripts/instagram_testers/browser-operations.mjs',
    'tests/instagram_testers/session-manager.test.mjs',
    'tests/instagram_testers/publisher-channel.test.mjs',
    'tests/instagram_testers/vps-publisher.test.mjs',
    'tests/qa/instagram-automation/warm-meta-page.mjs',
    'tests/qa/instagram-automation/route-stress.mjs',
)


def push_patterns(workflow):
    source = (ROOT / '.github/workflows' / workflow).read_text()
    match = re.search(r'(?ms)^  push:\n(.*?)(?=^  workflow_dispatch:)', source)
    if match is None:
        raise AssertionError('missing push trigger')
    return re.findall(r"^      - '([^']+)'$", match.group(1), re.MULTILINE)


def path_matches(pattern, path):
    # Existing workflow patterns use only '*' and '**'. Match '*' inside one
    # path segment and '**' across zero or more segments, as GitHub documents.
    parts = tuple(pattern.split('/'))
    segments = tuple(path.split('/'))

    def match(remaining, values):
        if not remaining:
            return not values
        if remaining[0] == '**':
            return match(remaining[1:], values) or bool(values) and match(remaining, values[1:])
        return bool(values) and fnmatch.fnmatchcase(values[0], remaining[0]) and match(remaining[1:], values[1:])

    return match(parts, segments)


def triggers(patterns, paths):
    for path in paths:
        included = False
        for pattern in patterns:
            excluded = pattern.startswith('!')
            if path_matches(pattern.lstrip('!'), path):
                included = not excluded
        if included:
            return True
    return False


class DeployRoutingTest(unittest.TestCase):
    def test_matcher_obeys_path_segment_boundaries(self):
        self.assertFalse(path_matches('*.md', 'app/manual.md'))
        self.assertTrue(path_matches('**/*.md', 'README.md'))
        self.assertTrue(path_matches('app/**/*.md', 'app/manual.md'))
        self.assertTrue(path_matches('app/**/*.md', 'app/services/agent/manual.md'))
        self.assertFalse(path_matches('app/**/*.md', 'lib/manual.md'))

    def test_exclusions_do_not_swallow_similar_production_files(self):
        paths = ('scripts/instagram_testers/session-manager.mjs.bak',
                 'scripts/instagram_testers/browser-operations.mjs.bak',
                 'scripts/instagram_testers/runtime/vps/systemd/instagram-vps-publisher@hub2you.service',
                 'tests/instagram_testers_extra/runner.mjs',
                 'tests/qa/instagram-automation-extra/runner.mjs')
        for workflow in WORKFLOWS:
            for path in paths:
                with self.subTest(workflow=workflow, path=path):
                    self.assertTrue(triggers(push_patterns(workflow), [path]))

    def test_both_stacks_use_the_same_path_policy(self):
        self.assertEqual(push_patterns(WORKFLOWS[0]), push_patterns(WORKFLOWS[1]))

    def test_each_vps_only_file_skips_aws_deploy(self):
        for workflow in WORKFLOWS:
            for path in VPS_ONLY:
                with self.subTest(workflow=workflow, path=path):
                    self.assertFalse(triggers(push_patterns(workflow), [path]))

    def test_complete_vps_candidate_skips_aws_deploy(self):
        paths = (*VPS_ONLY, 'docs/audit/release.json', '.github/workflows/instagram-tester-onboarding.yml')
        for workflow in WORKFLOWS:
            self.assertFalse(triggers(push_patterns(workflow), paths))

    def test_mixed_application_change_still_deploys(self):
        for workflow in WORKFLOWS:
            self.assertTrue(triggers(push_patterns(workflow), (*VPS_ONLY, 'app/controllers/instagram/callbacks_controller.rb')))

    def test_aws_publisher_and_shared_runtime_still_deploy(self):
        paths = ('scripts/instagram_testers/session_publisher.rb',
                 'scripts/instagram_testers/runtime/install-remote-publisher.sh',
                 'scripts/instagram_testers/runtime/publisher-channel.mjs',
                 'scripts/instagram_testers/runtime/operator-protocol.mjs')
        for workflow in WORKFLOWS:
            for path in paths:
                with self.subTest(workflow=workflow, path=path):
                    self.assertTrue(triggers(push_patterns(workflow), [path]))

    def test_other_vps_runtime_changes_still_deploy_conservatively(self):
        for workflow in WORKFLOWS:
            self.assertTrue(triggers(push_patterns(workflow), ['scripts/instagram_testers/runtime/vps/gateway.mjs']))

    def test_runtime_knowledge_still_deploys(self):
        paths = ('app/manual.md', 'app/services/autonomia/insurance/quote_agent/instrucoes/manual.md',
                 'lib/operator_guide/porques.md', 'lib/central_de_ajuda/help.md', 'config/onboarding/steps.yml')
        for workflow in WORKFLOWS:
            for path in paths:
                with self.subTest(workflow=workflow, path=path):
                    self.assertTrue(triggers(push_patterns(workflow), [path]))

    def test_application_dependencies_and_migrations_still_deploy(self):
        paths = ('Gemfile.lock', 'package.json', 'db/migrate/change.rb', 'docker/Dockerfile', '.dockerignore')
        for workflow in WORKFLOWS:
            for path in paths:
                with self.subTest(workflow=workflow, path=path):
                    self.assertTrue(triggers(push_patterns(workflow), [path]))

    def test_docs_and_workflows_remain_skipped(self):
        for workflow in WORKFLOWS:
            self.assertFalse(triggers(push_patterns(workflow), ['docs/report.json', '.github/workflows/testes.yml', 'README.md']))

    def test_manual_deploy_and_rollback_still_require_confirmation(self):
        for workflow in WORKFLOWS:
            source = (ROOT / '.github/workflows' / workflow).read_text()
            self.assertIn('  workflow_dispatch:', source)
            self.assertIn('      confirm_production:', source)
            self.assertIn('inputs.confirm_production == true', source)
            self.assertIn("inputs.action == 'rollback'", source)


if __name__ == '__main__':
    unittest.main()
