"""Offline tests; every cookie, token and ID below is invented.

Run: python3 -B tests/instagram_testers/test_prepare_session.py
"""

from contextlib import redirect_stderr, redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import shlex
import stat
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import urlencode


MODULE_PATH = Path(__file__).resolve().parents[2] / "scripts/instagram_testers/prepare_session.py"
SPEC = importlib.util.spec_from_file_location("prepare_session", MODULE_PATH)
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)

TYPEAHEAD = "https://developers.facebook.com/roles/instagram/typeahead/user/?value=%40demo_company"
ADD = "https://developers.facebook.com/apps/987654321/async/instagram/roles/add/"
GRAPHQL = "https://developers.facebook.com/api/graphql/"
COOKIE = "c_user=123456789; xs=SYNTHETIC_COOKIE_SECRET; datr=SYNTHETIC_BROWSER"
USER_AGENT = "Synthetic Chrome/1.0 (offline; tester)"
FIELDS = {
    "__user": "123456789", "fb_dtsg": "SYNTHETIC_DTSG_SECRET",
    "lsd": "SYNTHETIC_LSD_SECRET", "jazoest": "22001", "__a": "1",
    "__req": "a", "__dyn": "SYNTHETIC_DYN", "__unknown": "discarded",
}


def capture(url=TYPEAHEAD, fields=None, cookie=COOKIE, headers=None,
            body_flag="--data-raw", cookie_flag="-b", url_flag=False):
    # Quoting mirrors Chrome, rather than ever executing the assembled string.
    tokens = ["curl", *(["--url", url] if url_flag else [url]),
              "-H", "user-agent: " + USER_AGENT,
              "-H", "content-type: application/x-www-form-urlencoded",
              "-H", "x-fb-lsd: SYNTHETIC_LSD_SECRET"]
    if cookie_flag == "header":
        tokens.extend(("-H", "cookie: " + cookie))
    else:
        tokens.extend((cookie_flag, cookie))
    for name, value in (headers or {}).items():
        tokens.extend(("--header", name + ": " + value))
    tokens.extend((body_flag, urlencode(FIELDS if fields is None else fields)))
    return (" \\" + "\n  ").join(shlex.quote(token) for token in tokens)


class ParseCaptureTests(unittest.TestCase):
    def test_schema_and_allowlisted_instrumentation(self):
        result = prepare.parse_capture(capture())
        self.assertEqual(result, {
            "cookie": COOKIE, "user_id": "123456789", "user_agent": USER_AGENT,
            "fb_dtsg": "SYNTHETIC_DTSG_SECRET", "lsd": "SYNTHETIC_LSD_SECRET",
            "jazoest": "22001", "extra_form": {"__req": "a", "__dyn": "SYNTHETIC_DYN"},
        })

    def test_supported_chrome_flag_variants(self):
        for body_flag in ("--data-raw", "--data", "-d"):
            for cookie_flag in ("-b", "--cookie", "header"):
                with self.subTest(body_flag=body_flag, cookie_flag=cookie_flag):
                    text = capture(body_flag=body_flag, cookie_flag=cookie_flag, url_flag=True)
                    self.assertEqual(prepare.parse_capture(text + " --compressed --globoff -X POST")["cookie"], COOKIE)
        self.assertEqual(prepare.parse_capture(capture() + " --request POST")["user_id"], "123456789")

    def test_all_fixed_routes_and_only_session_ids_exported(self):
        add_fields = dict(FIELDS, role="instagram testers", **{"user_id_or_vanitys[0]": "17841400000000001"})
        graphql_fields = dict(FIELDS, fb_api_req_friendly_name="RolesTable_Query",
                              variables=json.dumps({"app_id": "987654321"}), doc_id="24715790494688123")
        for url, fields in ((TYPEAHEAD, FIELDS), (ADD, add_fields), (GRAPHQL, graphql_fields)):
            with self.subTest(url=url):
                result = prepare.parse_capture(capture(url=url, fields=fields))
                self.assertEqual(result["user_id"], "123456789")
                self.assertNotIn("987654321", json.dumps(result))
                self.assertNotIn("17841400000000001", json.dumps(result))

    def test_quoted_shell_text_is_preserved_without_execution(self):
        fields = dict(FIELDS, fb_dtsg="literal ' \" $(touch /never-create) `id` ; && secret")
        with patch("os.system", side_effect=AssertionError("Execution forbidden")):
            self.assertEqual(prepare.parse_capture(capture(fields=fields))["fb_dtsg"], fields["fb_dtsg"])

    def test_cookie_and_header_identity_must_match_body(self):
        for text in (capture(cookie="c_user=987654321; xs=SYNTHETIC"),
                     capture().replace("x-fb-lsd: SYNTHETIC_LSD_SECRET", "x-fb-lsd: OTHER_SECRET")):
            with self.subTest(text_length=len(text)), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(text)

    def test_all_required_fields_and_user_agent(self):
        for key in ("__user", "fb_dtsg", "lsd", "jazoest"):
            fields = dict(FIELDS)
            del fields[key]
            with self.subTest(key=key), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture(fields=fields))
        with self.assertRaises(prepare.PreparationError):
            prepare.parse_capture(capture().replace("user-agent:", "accept:"))

    def test_only_ascii_numeric_user_and_app_ids(self):
        for user_id in ("", "１２３", "١٢٣", "+123", "123.0", "12 3", "1" * 41):
            with self.subTest(user_id=user_id), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture(fields=dict(FIELDS, __user=user_id), cookie="c_user=" + user_id))
        for app_id in ("１２３", "abc", "1" * 41):
            with self.subTest(app_id=app_id), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture(url=ADD.replace("987654321", app_id)))

    def test_reject_commands_extra_urls_and_unsupported_flags(self):
        suffixes = (
            "; echo SYNTHETIC_SECRET", " && echo SYNTHETIC_SECRET", " | cat", "\necho secret",
            " https://developers.facebook.com/api/graphql/", " --url " + TYPEAHEAD,
            " --next", " --config /never-read", " -K /never-read", " --data-binary @/never-read",
            " --form fb_dtsg=@/never-read", " --output /never-write", " --upload-file /never-read",
            " --header @/never-read", " --cookie /never-read", " -X GET", " --compressed --compressed",
        )
        for suffix in suffixes:
            with self.subTest(suffix=suffix), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture() + suffix)
        for flag in ("--data", "-d"):
            with self.subTest(flag=flag), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture("curl " + shlex.quote(TYPEAHEAD) + " " + flag + " @/never-read")
        with patch("builtins.open", side_effect=AssertionError("Capture must not read files")):
            prepare.parse_capture(capture())

    def test_reject_unknown_hosts_and_paths(self):
        urls = (
            TYPEAHEAD.replace("https:", "http:"), TYPEAHEAD.replace("developers.facebook.com", "evil.example"),
            TYPEAHEAD.replace("developers.facebook.com", "developers.facebook.com.evil.example"),
            TYPEAHEAD.replace("developers.facebook.com", "evil@developers.facebook.com"),
            TYPEAHEAD.replace("developers.facebook.com", "developers.facebook.com:443"),
            TYPEAHEAD + "#fragment", TYPEAHEAD + "&other=1", TYPEAHEAD.replace("/roles/", "/other/"),
            TYPEAHEAD.replace("/roles/", "/%72oles/"), TYPEAHEAD.replace("?value=%40demo_company", ""),
            ADD + "?other=1", ADD.replace("/apps/", "/app/"),
        )
        for url in urls:
            with self.subTest(url=url), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture(url=url))

    def test_graphql_is_only_roles_table_query(self):
        fields = dict(FIELDS, fb_api_req_friendly_name="RolesTable_Query", variables='{"app_id":"987654321"}')
        invalid_fields = (
            dict(fields, fb_api_req_friendly_name="OtherQuery"), dict(fields, variables="{}"),
            dict(fields, variables='{"app_id":987654321}'), dict(fields, variables="not-json"),
            dict(fields, variables='{"app_id":"1","app_id":"2"}'),
            dict(fields, variables='{"app_id":"1","other":"2"}'),
        )
        for invalid in invalid_fields:
            with self.subTest(variables=invalid["variables"]), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture(url=GRAPHQL, fields=invalid))
        with self.assertRaises(prepare.PreparationError):
            prepare.parse_capture(capture(url=GRAPHQL, fields=fields, headers={"x-fb-friendly-name": "OtherQuery"}))

    def test_duplicate_header_cookie_and_form_fields(self):
        invalid_captures = (
            capture() + " -H 'User-Agent: duplicate'", capture() + " -b 'c_user=123456789'",
            capture(cookie=COOKIE + "; c_user=123456789"),
            capture() + " -H " + shlex.quote("cookie: " + COOKIE),
            capture(fields={**FIELDS, "%unused": "test"}).replace("__user=123456789", "__user=123456789&__user=123456789"),
            capture().replace("__user=123456789", "__user=123456789&%5F%5Fuser=123456789"),
        )
        for text in invalid_captures:
            with self.subTest(length=len(text)), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(text)

    def test_malformed_forms_and_unsafe_values(self):
        encoded = urlencode(FIELDS)
        bodies = (
            encoded + "&broken", encoded + "&", encoded + "&=value", encoded + "&extra=%ZZ",
            encoded + "&extra=%", encoded + "&extra=%FF", encoded + "&extra=%0aevil",
            encoded + "&extra=%0Devil", encoded + "&extra=%00evil", encoded + "&extra=%09evil",
            encoded.replace("lsd=SYNTHETIC_LSD_SECRET", "lsd="),
            encoded.replace("__req=a", "__req="), encoded + "&" + "&".join("k%d=x" % n for n in range(260)),
        )
        for body in bodies:
            with self.subTest(body_length=len(body)), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture().replace(shlex.quote(encoded), shlex.quote(body)))
        for value in ("line\nbreak", "line\rbreak", "line\x00break", "line\\\nbreak"):
            with self.subTest(value_length=len(value)), self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(capture(headers={"accept": value}))
        with self.assertRaises(prepare.PreparationError):
            prepare.parse_capture(capture(headers={"authorization": "unsupported"}))
        with self.assertRaises(prepare.PreparationError):
            prepare.parse_capture(capture().replace("application/x-www-form-urlencoded", "application/json"))

    def test_size_limit_and_unclosed_quotes(self):
        for text in (capture() + " " * prepare.MAX_INPUT_BYTES, capture() + " 'unclosed"):
            with self.assertRaises(prepare.PreparationError):
                prepare.parse_capture(text)


class PrivateOutputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="instagram-910-synthetic-")
        self.addCleanup(self.temporary.cleanup)
        # macOS /var and /tmp aliases are themselves symlinks; real paths only.
        self.root = Path(self.temporary.name).resolve()
        self.session = prepare.parse_capture(capture())
        self.output = self.root / "private" / "session.json"

    def test_new_directory_and_file_are_private(self):
        prepare.write_session(self.session, self.output)
        self.assertEqual(stat.S_IMODE(self.output.parent.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)
        self.assertEqual(json.loads(self.output.read_text()), self.session)
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_no_overwrite_without_explicit_replace(self):
        prepare.write_session(self.session, self.output)
        replacement = dict(self.session, fb_dtsg="NEW_SYNTHETIC_SECRET")
        with self.assertRaises(prepare.PreparationError):
            prepare.write_session(replacement, self.output)
        self.assertEqual(json.loads(self.output.read_text()), self.session)
        self.output.chmod(0o644)
        prepare.write_session(replacement, self.output, replace=True)
        self.assertEqual(json.loads(self.output.read_text()), replacement)
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o600)

    def test_public_directory_rejected(self):
        self.output.parent.mkdir(mode=0o755)
        # mkdir respects the caller umask; force the public mode under test.
        self.output.parent.chmod(0o755)
        with self.assertRaises(prepare.PreparationError):
            prepare.write_session(self.session, self.output)
        self.assertFalse(self.output.exists())

    def test_git_directory_and_worktree_marker_rejected(self):
        for marker_kind in ("directory", "file", "symlink"):
            root = self.root / marker_kind
            root.mkdir(mode=0o700)
            if marker_kind == "directory":
                (root / ".git").mkdir()
            elif marker_kind == "file":
                (root / ".git").write_text("gitdir: /synthetic-only")
            else:
                (root / ".git").symlink_to(self.root / "nonexistent")
            with self.subTest(kind=marker_kind), self.assertRaises(prepare.PreparationError):
                prepare.write_session(self.session, root / "nested" / "session.json")
            self.assertFalse((root / "nested").exists())

    def test_symlink_output_and_ancestors_rejected_even_with_replace(self):
        target = self.root / "target.json"
        target.write_text("untouched")
        link = self.root / "link.json"
        link.symlink_to(target)
        for replace in (False, True):
            with self.subTest(replace=replace), self.assertRaises(prepare.PreparationError):
                prepare.write_session(self.session, link, replace=replace)
        self.assertEqual(target.read_text(), "untouched")
        ancestor = self.root / "ancestor"
        ancestor.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            prepare.write_session(self.session, ancestor / "session.json")
        with self.assertRaises(prepare.PreparationError):
            prepare.write_session(self.session, ancestor / ".." / "session.json")

    def test_output_directory_cannot_be_replaced(self):
        self.output.mkdir(parents=True, mode=0o700)
        self.output.parent.chmod(0o700)
        with self.assertRaises(prepare.PreparationError):
            prepare.write_session(self.session, self.output, replace=True)

    def test_temp_cleanup_when_write_or_publication_fails(self):
        self.output.parent.mkdir(mode=0o700)
        for function in ("json.dump", "os.link", "os.fsync"):
            with self.subTest(function=function):
                with patch.object(prepare.json if function == "json.dump" else prepare.os,
                                  function.split(".")[1], side_effect=OSError("SYNTHETIC_PRIVATE_ERROR")):
                    with self.assertRaises(OSError):
                        prepare.write_session(self.session, self.output)
                self.assertEqual(list(self.output.parent.iterdir()), [])

    def test_exclusive_temp_creation_does_not_remove_an_existing_file(self):
        self.output.parent.mkdir(mode=0o700)
        existing = self.output.parent / ".instagram-session-synthetic-collision"
        existing.write_text("untouched")
        with patch.object(prepare.secrets, "token_hex", return_value="synthetic-collision"):
            with self.assertRaises(FileExistsError):
                prepare.write_session(self.session, self.output)
        self.assertEqual(existing.read_text(), "untouched")
        self.assertFalse(self.output.exists())

    def test_exclusive_publication_preserves_file_created_during_write(self):
        original_link = os.link

        def competing_publication(source, destination, **kwargs):
            self.output.write_text("competing-file")
            return original_link(source, destination, **kwargs)

        with patch.object(prepare.os, "link", side_effect=competing_publication):
            with self.assertRaises(FileExistsError):
                prepare.write_session(self.session, self.output)
        self.assertEqual(self.output.read_text(), "competing-file")
        self.assertEqual(list(self.output.parent.iterdir()), [self.output])

    def test_cli_success_is_silent(self):
        source = self.root / "synthetic-capture.txt"
        source.write_text(capture())
        stdout, stderr = io.StringIO(), io.StringIO()
        with redirect_stdout(stdout), redirect_stderr(stderr):
            code = prepare.main(["--input", str(source), "--output", str(self.output)])
        self.assertEqual(code, 0)
        self.assertEqual(stdout.getvalue(), "")
        self.assertEqual(stderr.getvalue(), "")
        self.assertEqual(json.loads(self.output.read_text()), self.session)

    def test_cli_errors_never_print_values_paths_or_exception_details(self):
        source = self.root / "SYNTHETIC_PATH_SECRET"
        output = self.root / "SYNTHETIC_OUTPUT_SECRET"
        source.write_text(capture() + " --unsupported SYNTHETIC_ARGUMENT_SECRET")
        argument_sets = (
            ["--input", str(source), "--output", str(output)],
            ["--input", str(source), "--output", str(output), "--bad=SYNTHETIC_ARGUMENT_SECRET"],
            ["--input", str(source), "--output"],
            ["--input", str(source) + "missing", "--output", str(output)],
        )
        for arguments in argument_sets:
            stdout, stderr = io.StringIO(), io.StringIO()
            with self.subTest(argument_count=len(arguments)), redirect_stdout(stdout), redirect_stderr(stderr):
                code = prepare.main(arguments)
            self.assertEqual(code, 2)
            self.assertEqual(stdout.getvalue(), "")
            self.assertEqual(stderr.getvalue(), "Session preparation failed; check the capture and private output path.\n")
        source.write_text(capture())
        with patch.object(prepare, "write_session", side_effect=OSError("SYNTHETIC_OS_SECRET")):
            stdout, stderr = io.StringIO(), io.StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                self.assertEqual(prepare.main(["--input", str(source), "--output", str(output)]), 2)
            self.assertNotIn("SYNTHETIC", stdout.getvalue() + stderr.getvalue())

    def test_cli_size_and_encoding_limits(self):
        source = self.root / "synthetic-capture.txt"
        for content in (b"x" * (prepare.MAX_INPUT_BYTES + 1), b"\xff"):
            source.write_bytes(content)
            with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
                self.assertEqual(prepare.main(["--input", str(source), "--output", str(self.output)]), 2)
            self.assertFalse(self.output.exists())


if __name__ == "__main__":
    unittest.main()
