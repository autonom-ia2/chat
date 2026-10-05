"""Bounded invalid-close diagnostics, never a WebSocket/protocol acceptance path.

Only fixed enums, integers and booleans leave this module. Bytes, reason text,
JSON objects, identifiers, URLs, tokens and payload hashes are never returned.
"""
import json

MAX_CLOSE_DIAGNOSTIC = 512
ERROR_CODES = frozenset({
    "AccessDenied", "AccessDeniedException", "Unauthorized", "UnauthorizedException",
    "InvalidToken", "InvalidTokenException", "ExpiredToken", "ExpiredTokenException",
    "ValidationException", "InvalidSessionId", "InvalidSessionIdException",
    "TargetNotConnected", "TargetNotConnectedException", "InternalServerError",
})
CODE_KEYS = ("Code", "code", "ErrorCode", "errorCode", "errorType", "__type")
HINTS = {
    "hint_access_denied": ("access denied", "accessdenied"),
    "hint_unauthorized": ("unauthorized", "not authorized", "not authorised"),
    "hint_invalid_token": ("invalid token", "token is invalid", "token is not valid"),
    "hint_expired": ("expired", "expiration"),
    "hint_mismatch": ("mismatch", "does not match", "not matching"),
    "hint_session_not_found": ("session not found", "session does not exist"),
}
ID_CHARS = frozenset("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
MAX_REASON_TERMS = 64
TERM_VOCABULARY = {word: word.upper() for word in (
    "a", "an", "the", "and", "or", "but", "as", "at", "by", "for", "from", "in", "of", "on", "to", "with",
    "not", "no", "without", "never", "neither", "nor", "does", "do", "did", "is", "are", "was", "were", "be", "has", "have",
    "session", "id", "identifier", "token", "claim", "request", "message", "channel", "stream", "url", "path", "header", "input", "data",
    "equal", "equals", "different", "differs", "same", "expected", "actual", "match", "matches", "mismatch",
    "validate", "validation", "valid", "invalid", "required", "provided", "supplied", "found", "failed", "cannot",
    "accept", "accepted", "rejected", "denied", "allowed", "unsupported", "received", "contains",
    "if", "unless", "except", "only", "than",
)}
TERM_VOCABULARY.update({
    "sessionid": "SESSION_ID", "session_id": "SESSION_ID", "session-id": "SESSION_ID",
    "requestid": "REQUEST_ID", "request_id": "REQUEST_ID", "request-id": "REQUEST_ID",
    "clientid": "CLIENT_ID", "client_id": "CLIENT_ID", "client-id": "CLIENT_ID",
    "tokenvalue": "TOKEN_VALUE", "token_value": "TOKEN_VALUE", "streamurl": "STREAM_URL",
    "stream_url": "STREAM_URL", "schema": "SCHEMA", "version": "VERSION",
})
for contraction, label in (
    ("doesn't", "DOES_NOT"), ("don't", "DO_NOT"), ("didn't", "DID_NOT"),
    ("isn't", "IS_NOT"), ("aren't", "ARE_NOT"), ("wasn't", "WAS_NOT"), ("weren't", "WERE_NOT"),
    ("can't", "CANNOT"), ("couldn't", "COULD_NOT"), ("won't", "WILL_NOT"),
    ("wouldn't", "WOULD_NOT"), ("shouldn't", "SHOULD_NOT"),
    ("hasn't", "HAS_NOT"), ("haven't", "HAVE_NOT"), ("hadn't", "HAD_NOT"),
):
    TERM_VOCABULARY[contraction] = label
    TERM_VOCABULARY[contraction.replace("'", "’")] = label
TERM_OPERATORS = {"=": "EQUAL_OP", "==": "EQUAL_OP", "===": "STRICT_EQUAL_OP",
                  "!=": "NOT_EQUAL_OP", "<>": "NOT_EQUAL_OP", "!==": "STRICT_NOT_EQUAL_OP",
                  "<": "LESS_THAN_OP", ">": "GREATER_THAN_OP", "<=": "LESS_OR_EQUAL_OP", ">=": "GREATER_OR_EQUAL_OP"}


def ordered_reason_terms(reason, own_session_id, foreign_session_id):
    """Project lexical order with fixed terms only; no semantic/access verdict."""
    result = {"status": "out_of_scope", "terms": [], "truncated": False, "max_terms": MAX_REASON_TERMS}
    if not isinstance(reason, str):
        return result
    try:
        if len(reason.encode("utf-8", errors="strict")) > MAX_CLOSE_DIAGNOSTIC-2:
            return result
    except UnicodeError:
        return result
    ids_valid = (isinstance(own_session_id, str) and isinstance(foreign_session_id, str) and
                 own_session_id != foreign_session_id and 0 < len(own_session_id) <= 96 and
                 0 < len(foreign_session_id) <= 96 and all(c in ID_CHARS for c in own_session_id) and
                 all(c in ID_CHARS for c in foreign_session_id))
    result["status"] = "observed"

    def emit(label):
        if result["terms"] and label == "OTHER" and result["terms"][-1] == "OTHER":
            return
        if len(result["terms"]) == MAX_REASON_TERMS:
            result["truncated"] = True
            return
        result["terms"].append(label)

    def atom(value):
        value = value.strip("'\"‘’“”")
        # Placeholders are never vocabulary keys: exact known IDs only, before
        # lowercasing. Unknown prefixes/suffixes remain a single OTHER atom.
        if ids_valid and value == own_session_id:
            return "OWN_SESSION"
        if ids_valid and value == foreign_session_id:
            return "FOREIGN_SESSION"
        return TERM_VOCABULARY.get(value.lower(), "OTHER")

    for chunk in reason.split():
        # Do not mine vocabulary or identifier context from URLs/opaque spans.
        core = chunk.strip("()[]{}<>,;.!?'\"‘’“”")
        if chunk in TERM_OPERATORS:
            emit(TERM_OPERATORS[chunk])
        elif "://" in chunk or any(c in core for c in "/\\@#=."):
            emit("OTHER")
        else:
            value = []
            for char in chunk:
                if char.isalnum() or char in "_-'’" or ord(char) >= 128:
                    value.append(char)
                else:
                    if value:
                        emit(atom("".join(value))); value = []
                    emit("OTHER")
                if result["truncated"]:
                    break
            if value and not result["truncated"]:
                emit(atom("".join(value)))
        if result["truncated"]:
            break
    return result


def _object_without_duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate_json_key")
        result[key] = value
    return result


def _invalid_constant(value):
    raise ValueError("non_json_constant")


def _session_context(text, own, foreign):
    valid = (isinstance(own, str) and isinstance(foreign, str) and own != foreign and
             0 < len(own) <= 96 and 0 < len(foreign) <= 96 and
             all(c in ID_CHARS for c in own) and all(c in ID_CHARS for c in foreign))
    if not valid:
        return "unknown", False
    # Exact identifier tokens; not a substring match and no token is exported.
    tokens, current = set(), []
    for char in text:
        if char in ID_CHARS:
            current.append(char)
        elif current:
            tokens.add("".join(current)); current = []
    if current:
        tokens.add("".join(current))
    own_found, foreign_found = own in tokens, foreign in tokens
    relation = "both" if own_found and foreign_found else "own" if own_found else "foreign" if foreign_found else "not_present"
    return relation, own_found or foreign_found


def project_close(payload, own_session_id, foreign_session_id):
    """Project at most512 bytes in memory; lexical hints never classify refusal."""
    result = {"protocol_frame_valid": False, "authentication_classified": False,
              "access_classified": False, "cutover_eligible": False,
              "projection_status": "out_of_scope", "close_code_present": False,
              "utf8_valid": False, "reason_format": "unobserved", "reason_bytes": 0,
              "typed_error_code": "unrecognized", "typed_error_code_format": "none",
              "reason_evidence_kind": "unknown", "session_id_relation": "unknown",
              "known_session_context_valid": False,
              "ordered_reason_terms": {"status": "unobserved", "terms": [], "truncated": False, "max_terms": MAX_REASON_TERMS},
              **{name: False for name in HINTS}}
    if not isinstance(payload, bytes) or not 126 <= len(payload) <= MAX_CLOSE_DIAGNOSTIC:
        return result
    result.update(projection_status="observed", close_code_present=True,
                  close_code=int.from_bytes(payload[:2], "big"), reason_bytes=len(payload)-2)
    try:
        reason = payload[2:].decode("utf-8", errors="strict")
    except UnicodeDecodeError:
        result["reason_format"] = "invalid_utf8"
        return result
    result["utf8_valid"] = True
    result["ordered_reason_terms"] = ordered_reason_terms(reason, own_session_id, foreign_session_id)
    result["session_id_relation"], result["known_session_context_valid"] = _session_context(reason, own_session_id, foreign_session_id)
    lowered = " ".join(reason.lower().split())
    for key, phrases in HINTS.items():
        result[key] = any(phrase in lowered for phrase in phrases)
    stripped = reason.strip()
    raw_codes = []
    try:
        parsed = json.loads(stripped, object_pairs_hook=_object_without_duplicates, parse_constant=_invalid_constant)
    except (ValueError, RecursionError):
        result["reason_format"] = "text_or_unrecognized_json"
        for code in ERROR_CODES:
            if stripped.startswith(code + ":"):
                raw_codes.append(code)
                result["typed_error_code_format"] = "text_code_prefix"
    else:
        result["reason_format"] = "json_object" if isinstance(parsed, dict) else "json_non_object"
        if isinstance(parsed, dict):
            containers = [parsed]
            if isinstance(parsed.get("Error"), dict):
                containers.append(parsed["Error"])
            for container in containers:
                for key in CODE_KEYS:
                    if key in container:
                        value = container[key]
                        # Unknown namespaces/prefixes remain unknown; do not
                        # salvage an allowlisted suffix from arbitrary text.
                        raw_codes.append(value if isinstance(value, str) else None)
            if raw_codes:
                result["typed_error_code_format"] = "json_code_field"
    if raw_codes and all(isinstance(code, str) and code in ERROR_CODES for code in raw_codes) and len(set(raw_codes)) == 1:
        result["typed_error_code"] = raw_codes[0]
        result["reason_evidence_kind"] = "typed_code_with_session_context" if result["known_session_context_valid"] else "typed_code_only"
    elif raw_codes:
        result["typed_error_code_format"] = "ambiguous_or_unrecognized"
    if result["typed_error_code"] == "unrecognized" and any(result[key] for key in HINTS):
        result["reason_evidence_kind"] = "lexical_hints_only"
    return result


def capture_invalid_close(reader, own_session_id, foreign_session_id, *, max_frame, max_total, max_frames, stopped_type):
    """One diagnostic read after rejection, only close126..512, within old caps.

    The caller must retain control_frame_invalid, skip the protocol parser and
    close immediately. No retry/second frame/ACK/response is performed here.
    """
    result = {"scope": "invalid_close_diagnostic_only", "protocol_frame_valid": False,
              "access_classified": False, "cutover_eligible": False,
              "read_attempted": False, "complete": False, "status": "not_read",
              "reason": "not_eligible", "requested_payload_bytes": 0, "received_payload_bytes": 0}
    header = reader.control_rejection
    if not isinstance(header, dict) or header.get("frame_kind") != "close" or header.get("reason") != "control_payload_over_125":
        return result
    length = header.get("declared_payload_bytes")
    if type(length) is not int or not 126 <= length <= MAX_CLOSE_DIAGNOSTIC:
        result["reason"] = "diagnostic_byte_limit"
        return result
    if getattr(reader, "invalid_close_diagnostic_attempted", False):
        result["reason"] = "already_attempted"
        return result
    reader.invalid_close_diagnostic_attempted = True
    if length > max_frame or reader.frames >= max_frames or reader.payload_bytes + length > max_total:
        result["reason"] = "existing_frame_or_total_limit"
        return result
    before_wire = reader.wire_bytes
    payload = None
    try:
        reader.remaining()
        # Reserve the declared budget before receiving even a partial payload.
        reader.frames += 1
        reader.payload_bytes += length
        result.update(read_attempted=True, status="incomplete", reason="transport_error", requested_payload_bytes=length)
        payload = reader.exact(length)
        result["metadata"] = project_close(payload, own_session_id, foreign_session_id)
        result.update(complete=True, status="observed", reason="bounded_close_projected")
    except Exception as error:
        result["status"] = "incomplete"
        # Never format a dependency exception; only our reader's fixed enums.
        value = error.args[0] if isinstance(error, stopped_type) and len(error.args) == 1 else None
        result["reason"] = value if isinstance(value, str) and value in {"time_limit", "peer_eof", "frame_byte_limit", "transport_error"} else "transport_error"
    finally:
        result["received_payload_bytes"] = min(MAX_CLOSE_DIAGNOSTIC, max(0, reader.wire_bytes-before_wire))
        payload = None
    return result
