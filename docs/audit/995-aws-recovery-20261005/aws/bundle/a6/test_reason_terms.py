"""Focused pure A6 projection fixtures; no AWS/VPS/process/network calls."""
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import struct
import unittest

import ssm_close_diagnostic as subject

HERE = Path(__file__).resolve().parent
OWN = "igpub-hub2you-vps-synthetic001"
FOREIGN = "cursor-hub2you-synthetic002"
PRIVATE = "PRIVATE_ORDERED_REASON_SENTINEL"
URL = "wss://private.invalid/session/not/"+OWN
TOKEN = "session.not.valid/private#opaque=="


def terms(reason, own=OWN, foreign=FOREIGN):
    return subject.ordered_reason_terms(reason, own, foreign)


class OrderedTerms(unittest.TestCase):
    def assert_public(self, result):
        raw = json.dumps(result, ensure_ascii=False)
        for value in (OWN, FOREIGN, PRIVATE, URL, TOKEN):
            self.assertNotIn(value, raw)
        allowed = set(subject.TERM_VOCABULARY.values()) | set(subject.TERM_OPERATORS.values()) | {"OTHER", "OWN_SESSION", "FOREIGN_SESSION"}
        self.assertTrue(all(value in allowed for value in result["terms"]))
        self.assertLessEqual(len(result["terms"]), subject.MAX_REASON_TERMS)

    def test_order_negation_comparisons_and_swapped_sessions(self):
        cases = (
            ("session id "+FOREIGN+" does not equal session id "+OWN,
             ["SESSION", "ID", "FOREIGN_SESSION", "DOES", "NOT", "EQUAL", "SESSION", "ID", "OWN_SESSION"]),
            ("expected session_id "+OWN+" but received session_id "+FOREIGN,
             ["EXPECTED", "SESSION_ID", "OWN_SESSION", "BUT", "RECEIVED", "SESSION_ID", "FOREIGN_SESSION"]),
            ("no channel without valid token", ["NO", "CHANNEL", "WITHOUT", "VALID", "TOKEN"]),
            ("not denied", ["NOT", "DENIED"]),
            ("session differs from request", ["SESSION", "DIFFERS", "FROM", "REQUEST"]),
            ("denied unless session valid", ["DENIED", "UNLESS", "SESSION", "VALID"]),
            ("only if token valid except different session", ["ONLY", "IF", "TOKEN", "VALID", "EXCEPT", "DIFFERENT", "SESSION"]),
        )
        for reason, expected in cases:
            result = terms(reason)
            self.assertEqual(result["terms"], expected)
            self.assertFalse(result["truncated"])
            self.assert_public(result)

    def test_atomic_operators_keep_comparisons_distinct_without_mining_spans(self):
        expected_operators = (("=", "EQUAL_OP"), ("==", "EQUAL_OP"), ("===", "STRICT_EQUAL_OP"),
                              ("!=", "NOT_EQUAL_OP"), ("<>", "NOT_EQUAL_OP"), ("!==", "STRICT_NOT_EQUAL_OP"),
                              ("<", "LESS_THAN_OP"), (">", "GREATER_THAN_OP"), ("<=", "LESS_OR_EQUAL_OP"), (">=", "GREATER_OR_EQUAL_OP"))
        for operator, label in expected_operators:
            result = terms(OWN+" "+operator+" "+FOREIGN)
            self.assertEqual(result["terms"], ["OWN_SESSION", label, "FOREIGN_SESSION"])
            self.assert_public(result)
        self.assertNotEqual(terms(OWN+" == "+FOREIGN)["terms"], terms(OWN+" != "+FOREIGN)["terms"])
        for opaque in (OWN+"=="+FOREIGN, "!=<>", "?session="+OWN, "https://private.invalid/?session!="+FOREIGN):
            result = terms(opaque)
            self.assertEqual(result["terms"], ["OTHER"])
            self.assert_public(result)

    def test_contractions_quotes_and_case_preserve_negation(self):
        for word, expected in (("doesn't", "DOES_NOT"), ("isn't", "IS_NOT"), ("can't", "CANNOT"),
                               ("won't", "WILL_NOT"), ("don't", "DO_NOT"), ("shouldn't", "SHOULD_NOT")):
            for variant in (word, word.upper(), word.replace("'", "’"), "'"+word+"'"):
                result = terms(variant)
                self.assertEqual(result["terms"], [expected])
                self.assert_public(result)
        self.assertEqual(terms("“not”")["terms"], ["NOT"])

    def test_placeholders_require_exact_ids_without_suffix_salvage(self):
        result = terms("OWN_SESSION FOREIGN_SESSION")
        self.assertEqual(result["terms"], ["OTHER"])
        self.assertNotIn("own_session", subject.TERM_VOCABULARY)
        self.assertNotIn("foreign_session", subject.TERM_VOCABULARY)
        for invalid in ("x"+OWN, OWN+"extra", OWN+"-extra", "_"+OWN, OWN+"_extra", OWN+"é",
                        FOREIGN.upper(), "prefix"+FOREIGN):
            result = terms(invalid)
            self.assertNotIn("OWN_SESSION", result["terms"])
            self.assertNotIn("FOREIGN_SESSION", result["terms"])
            self.assert_public(result)
        result = terms("("+OWN+") '"+FOREIGN+"'")
        self.assertEqual([x for x in result["terms"] if x != "OTHER"], ["OWN_SESSION", "FOREIGN_SESSION"])
        self.assert_public(result)
        self.assertNotIn("OWN_SESSION", terms(OWN, OWN, OWN)["terms"])
        self.assertNotIn("OWN_SESSION", terms(OWN, "invalid known id", FOREIGN)["terms"])

    def test_private_unknown_spans_urls_and_tokens_are_only_other(self):
        result = terms("not "+PRIVATE+" "+URL+" "+TOKEN+" equal")
        self.assertEqual(result["terms"], ["NOT", "OTHER", "EQUAL"])
        self.assert_public(result)
        self.assertEqual(terms("session/private#not")["terms"], ["OTHER"])
        self.assertEqual(terms("prefix#session")["terms"], ["OTHER"])

    def test_unicode_unknown_atoms_do_not_salvage_known_words(self):
        result = terms("prénot 界session ＮＯＴ "+PRIVATE+" token")
        self.assertEqual(result["terms"], ["OTHER", "TOKEN"])
        self.assert_public(result)
        self.assertEqual(terms("doesn’t match")["terms"], ["DOES_NOT", "MATCH"])

    def test_term_limit_late_negation_and_byte_limit_are_explicit(self):
        result = terms("id "*subject.MAX_REASON_TERMS+"not")
        self.assertEqual(result["terms"], ["ID"]*subject.MAX_REASON_TERMS)
        self.assertTrue(result["truncated"])
        self.assert_public(result)
        result = terms("x"*(subject.MAX_CLOSE_DIAGNOSTIC-2))
        self.assertEqual(result["status"], "observed")
        self.assertFalse(result["truncated"])
        for out_of_scope in ("x"*(subject.MAX_CLOSE_DIAGNOSTIC-1), "é"*256, "\ud800", b"not"):
            result = terms(out_of_scope)
            self.assertEqual(result["status"], "out_of_scope")
            self.assertEqual(result["terms"], [])
            self.assert_public(result)

    def test_project_close_adds_only_ordered_observation(self):
        reason = "session id "+FOREIGN+" is different from session id "+OWN
        raw = struct.pack(">H", 1003)+reason.encode()
        raw += b" "*max(0, 175-len(raw))
        result = subject.project_close(raw, OWN, FOREIGN)
        ordered = result.pop("ordered_reason_terms")
        self.assertEqual(ordered["terms"], ["SESSION", "ID", "FOREIGN_SESSION", "IS", "DIFFERENT", "FROM", "SESSION", "ID", "OWN_SESSION"])
        self.assert_public(ordered)
        baseline_path = HERE/"ssm_close_diagnostic-a5-baseline.py"
        spec = importlib.util.spec_from_file_location("a5_baseline_for_terms", baseline_path)
        baseline = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(baseline)
        self.assertEqual(result, baseline.project_close(raw, OWN, FOREIGN))
        for key in ("protocol_frame_valid", "authentication_classified", "access_classified", "cutover_eligible"):
            self.assertFalse(result[key])


if __name__ == "__main__":
    output = io.StringIO()
    result = unittest.TextTestRunner(stream=output, verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(OrderedTerms))
    files = ("ssm_close_diagnostic.py", "preflight-live-proofs-auth-candidate.py", "auth_diagnostic.py",
             "probe-client-auth-candidate.py", "service-proof-auth-candidate.py", "ssm_metadata.py", "test_reason_terms.py")
    receipt = {"tests": result.testsRun, "failures": len(result.failures), "errors": len(result.errors),
               "success": result.wasSuccessful(), "AWS_VPS_network_calls": 0,
               "scope": "Pure closed vocabulary order, negations/contractions, exact ID placeholders, unknown/private spans, Unicode, byte/term caps, unchanged A5 classification",
               "source_sha256": {name: hashlib.sha256((HERE/name).read_bytes()).hexdigest() for name in files}}
    (HERE/"auth-a6-fixture-result.json").write_text(json.dumps(receipt, indent=2)+"\n")
    log = output.getvalue()
    for private in (PRIVATE, URL, TOKEN, OWN, FOREIGN):
        log = log.replace(private, "[synthetic-redacted]")
    (HERE/"auth-a6-fixture.log").write_text(log)
    print(json.dumps(receipt, indent=2)); print(log)
    raise SystemExit(0 if result.wasSuccessful() else 1)
