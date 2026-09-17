#!/usr/bin/env python3
"""Read-only, deterministic file selection for issue 436's bounded CI gate."""

import os
from pathlib import Path
import re
import subprocess
import sys


FEATURE = re.compile(
    r"email[_-](campaign|sender|suppression|reputation|provider|event|template)"
    r"|email(Campaign|Sender|Suppression|Reputation|Provider|Event|Template)"
    r"|Email(Campaign|Sender|Suppression|Reputation|Provider|Event|Template|Protection)"
    r"|RecipientImport|recipientImport|CrmCampaignManagement|CampaignLayout"
)
UI_ROOT = "app/javascript/dashboard/components-next/Campaigns/EmailProtection/"
BASELINE_SPECS = {
    "spec/models/account_spec.rb",
    "spec/models/working_hour_spec.rb",
    "spec/enterprise/models/account_spec.rb",
    "spec/models/email_template_spec.rb",
    "spec/services/email_campaigns/ses/sender_spec.rb",
    "spec/services/email_campaigns/ses/event_destination_ensurer_spec.rb",
}
PREREQUISITES = {
    ".github/workflows/email-protection.yml", ".ruby-version", "Gemfile", "Gemfile.lock",
    "package.json", "pnpm-lock.yaml", "config/database.yml", "config/storage.yml",
    "config/environments/test.rb", "config/application.rb", "config/boot.rb",
    "config/environment.rb", "config/routes.rb", "config/vite.json", "db/schema.rb",
    "spec/spec_helper.rb", "spec/rails_helper.rb", ".rspec", ".rubocop.yml",
    ".rubocop_todo.yml", "vite.config.ts", "vite.shared.ts", "vitest.config.ts",
    "vitest.config.js", "vitest.setup.js", "vitest.i18n.js", "tailwind.config.js",
    "spec/factories/accounts.rb", "spec/factories/email_template.rb",
    "tests/playwright/package.json", "tests/playwright/package-lock.json",
    "tests/playwright/pnpm-lock.yaml",
}


def git(*args):
    return subprocess.check_output(["git", *args]).decode().rstrip("\n")


def tracked():
    return sorted(p for p in git("ls-files", "-z").split("\0") if p and Path(p).is_file())


def changes(base, head, include_deleted=False):
    args = ["diff", "--name-only", "-z"]
    if not include_deleted:
        args.append("--diff-filter=ACMRT")
    return sorted(p for p in git(*args, base, head, "--").split("\0") if p)


def relevant(path):
    return bool(
        FEATURE.search(path) or path in PREREQUISITES or path in BASELINE_SPECS
        or path.startswith((".github/scripts/email-protection", "spec/support/"))
        or re.search(r"/i18n/locale/[^/]+/(campaign|crm|index)\.(json|js)$", path)
    )


def select(mode, files):
    if mode == "rspec":
        return [p for p in files if p.startswith("spec/") and p.endswith("_spec.rb")
                and (FEATURE.search(p) or p in BASELINE_SPECS)]
    if mode == "pure":
        return [p for p in files if p.endswith("_test.rb") and p.startswith((
            "spec/pure/email_campaigns/", "spec/services/email_campaigns/reputation/"))]
    if mode == "frontend":
        return [p for p in files if p.startswith("app/javascript/")
                and re.search(r"\.(spec|test)\.[cm]?[jt]sx?$", p)
                and (FEATURE.search(p) or "/specs/campaigns/" in p
                     or p.endswith("/api/specs/campaign.spec.js"))]
    if mode == "ruby-lint":
        return [p for p in files if p.endswith((".rb", ".rake"))
                and p != "db/schema.rb" and Path(p).is_file()]
    if mode == "frontend-lint":
        return [p for p in files if p.startswith("app/javascript/")
                and p.endswith((".js", ".vue")) and relevant(p) and Path(p).is_file()]
    raise ValueError(f"Unknown selection: {mode}")


def main():
    mode = sys.argv[1]
    files = tracked()
    if mode == "scope":
        # Use the real PR head, not GitHub's synthetic merge commit, for lineage.
        head = os.environ["CI_HEAD_SHA"]
        baseline = git("merge-base", "refs/remotes/origin/main", head)
        branch = os.environ["CI_HEAD_BRANCH"]
        event_base = os.environ.get("CI_BASE_SHA") or baseline
        scoped = bool(re.search(r"(^|/)436(?:[-/]|$)", branch)) or any(
            relevant(p) for p in changes(event_base, head, include_deleted=True)
        )
        print(f"run={str(scoped).lower()}")
        print(f"ui={str(any(p.startswith(UI_ROOT) for p in files)).lower()}")
        print(f"baseline={baseline}")
        return
    if mode.endswith("-lint"):
        files = changes(os.environ["FEATURE_BASELINE"], os.environ["CI_HEAD_SHA"])
    selected = select(mode, files)
    if mode in {"rspec", "pure", "frontend"} and not selected:
        raise SystemExit(f"Empty {mode} selection: refusing a false-green gate")
    if mode == "rspec" and not BASELINE_SPECS.issubset(selected):
        raise SystemExit("Required bounded regression spec missing")
    for path in selected:
        sys.stdout.buffer.write(path.encode() + b"\0")


if __name__ == "__main__":
    main()
