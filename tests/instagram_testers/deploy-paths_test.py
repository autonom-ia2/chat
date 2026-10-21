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
    'scripts/instagram_testers/runtime/vps/release/vps_release.py',
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
                 'scripts/instagram_testers/runtime/vps/release.mjs',
                 'scripts/instagram_testers/runtime/vps/release-notes/x.mjs',
                 'scripts/instagram_testers/runtime/release/x.mjs',
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


def build_step(workflow):
    lines = (ROOT / '.github/workflows' / workflow).read_text().splitlines()
    start = lines.index('      - name: Build and push image')
    step = [lines[start]]
    for line in lines[start + 1:]:
        if line.startswith(('      - ', '      #')) or (line and not line.startswith('        ')):
            break
        step.append(line)
    return step


def locked_grpc_versions():
    # Só a gem do código-fonte (force_ruby_platform): linhas com plataforma, como 1.72.0-x86_64-linux, ficam de fora.
    versions = [line.strip()[len('grpc ('):-1] for line in (ROOT / 'Gemfile.lock').read_text().splitlines()
                if line.startswith('    grpc (') and line.endswith(')')]
    return [version for version in versions if '-' not in version]


class DeployImageBuildTest(unittest.TestCase):
    """#2012: o build da imagem reaproveita o cache sem abrir mão da segurança."""

    def dockerfile(self):
        return (ROOT / 'docker/Dockerfile').read_text().splitlines()

    def test_grpc_layer_matches_gemfile_lock(self):
        # Versão divergente não quebra a imagem (o bundle instala a do lock), mas volta a recompilar o grpc a cada
        # troca de gem e deixa uma cópia sobrando na imagem.
        args = [line.split('=', 1)[1] for line in self.dockerfile() if line.startswith('ARG GRPC_VERSION=')]
        self.assertEqual(len(args), 1)
        self.assertEqual(locked_grpc_versions(), args)

    def test_grpc_layer_comes_after_build_deps_and_before_the_gemfile(self):
        lines = self.dockerfile()
        deps = next(i for i, line in enumerate(lines) if line.startswith('RUN apk') and 'linux-headers' in line)
        grpc = next(i for i, line in enumerate(lines) if line.startswith('RUN gem install grpc '))
        gemfile = lines.index('COPY Gemfile Gemfile.lock ./')
        bundle = next(i for i, line in enumerate(lines) if 'bundle install -j' in line)
        self.assertLess(deps, grpc)
        self.assertLess(grpc, gemfile)
        self.assertLess(gemfile, bundle)
        command = ' '.join(lines[grpc:grpc + 2])
        for flag in ('-v "$GRPC_VERSION"', '--platform ruby', '--ignore-dependencies',
                     '--install-dir "$BUNDLE_PATH/ruby/3.4.0"'):
            self.assertIn(flag, command)

    def test_both_stacks_build_the_image_the_same_way(self):
        self.assertEqual(build_step(WORKFLOWS[0]), build_step(WORKFLOWS[1]))

    def test_layer_cache_stays_in_the_private_ecr(self):
        # O cache do Actions (type=gha) de um repositório público é restaurável por PR de fork; o do ECR privado, não.
        for workflow in WORKFLOWS:
            step = '\n'.join(build_step(workflow))
            with self.subTest(workflow=workflow):
                self.assertIn('cache-from: type=registry,ref=${{ steps.ecr.outputs.registry }}/', step)
                self.assertIn('cache-to: type=registry,ref=${{ steps.ecr.outputs.registry }}/', step)
                self.assertIn('mode=max', step)
                for leak in ('type=gha', 'type=local', 'type=inline', 'build-args', 'secrets', 'secret-files'):
                    self.assertNotIn(leak, step)


if __name__ == '__main__':
    unittest.main()
