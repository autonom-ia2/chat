"""Pure, bounded SSM metadata observation; no authentication verdict or I/O.

The caller must bound WebSocket reads/reassembly BEFORE allocating a complete
payload. These functions cannot undo an unbounded allocation by the transport.
Source layout: official AWS plugin clientmessage.go/messageparser.go, commit
930a08e65d3a378eeeebb7f1bcf67eae7d860ae0. See SOURCE_INDEX.json and README.md.
"""
import hashlib
import hmac
import json
import struct

MAX_FRAME_BYTES = 64 * 1024
MAX_TOTAL_BYTES = 256 * 1024
MAX_FRAMES = 32
MAX_ELAPSED_MS = 10_000
MAX_JSON_DEPTH = 32
HEADER_LENGTH = 116
PAYLOAD_OFFSET = 120

FRAME_KINDS = frozenset(('text', 'binary', 'ping', 'pong', 'close'))
MESSAGE_TYPES = frozenset((
    'output_stream_data', 'acknowledge', 'channel_closed',
    'start_publication', 'pause_publication',
))
PAYLOAD_TYPES = {
    1: 'output', 2: 'error', 3: 'size', 4: 'parameter',
    5: 'handshake_request', 6: 'handshake_response',
    7: 'handshake_complete', 8: 'encryption_challenge_request',
    9: 'encryption_challenge_response', 10: 'flag',
    11: 'stderr', 12: 'exit_code',
}
HINTS = (
    ('hint_access_denied', 'access denied'),
    ('hint_unauthorized', 'unauthorized'),
    ('hint_invalid_token', 'invalid token'),
    ('hint_expired', 'expired'),
    ('hint_mismatch', 'mismatch'),
)


def _empty(kind='unknown', size=0):
    result = {
        'diagnostic_only': True,
        'authentication_classified': False,
        'access_classified': False,
        'frame_kind': kind,
        'frame_bytes': size,
        'parse_status': 'unknown',
        'reason': 'unrecognized_frame_kind',
        'header_valid': False,
        'length_valid': False,
        'schema_known': False,
        'payload_digest': 'not_checked',
        'message_type': 'unknown',
        'payload_type': 'unknown',
        'payload_bytes': 0,
        'json_status': 'not_parsed',
        'session_id_relation': 'not_present',
        'known_session_context_valid': False,
        'output_text_present': False,
        'handshake_action_count': 0,
        'handshake_session_type_actions': 0,
        'handshake_kms_actions': 0,
        'handshake_unknown_actions': 0,
        'handshake_complete_observed': False,
        'customer_message_present': False,
        'close_code': 0,
        'close_reason_present': False,
    }
    result.update({key: False for key, _ in HINTS})
    return result


def _reject(result, reason, status='malformed'):
    result['parse_status'] = status
    result['reason'] = reason
    return result


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate_json_key')
        result[key] = value
    return result


def _constant(_value):
    raise ValueError('nonfinite_json_constant')


def _depth_bounded(payload):
    # Cheap preflight before JSON allocates nested containers. This is not a
    # JSON parser: the decoder still validates syntax/UTF-8/duplicate keys.
    depth = 0
    quoted = False
    escaped = False
    for byte in payload:
        if quoted:
            if escaped:
                escaped = False
            elif byte == 92:
                escaped = True
            elif byte == 34:
                quoted = False
        elif byte == 34:
            quoted = True
        elif byte in (91, 123):
            depth += 1
            if depth > MAX_JSON_DEPTH:
                return False
        elif byte in (93, 125):
            depth -= 1
    return True


def _json_object(payload, result):
    if not _depth_bounded(payload):
        result['json_status'] = 'depth_limit'
        return None
    try:
        value = json.loads(payload.decode('utf-8'), object_pairs_hook=_object,
                           parse_constant=_constant)
    except (UnicodeError, ValueError, RecursionError):
        result['json_status'] = 'invalid'
        return None
    if type(value) is not dict:
        result['json_status'] = 'not_object'
        return None
    result['json_status'] = 'valid_object'
    return value


def _known_ids(own_session_id, foreign_session_id):
    return (type(own_session_id) is str and 1 <= len(own_session_id) <= 96
            and (foreign_session_id is None or
                 (type(foreign_session_id) is str and 1 <= len(foreign_session_id) <= 96
                  and own_session_id != foreign_session_id)))


def _closed(value, result, own_session_id, foreign_session_id):
    session_id = value.get('SessionId')
    valid_context = _known_ids(own_session_id, foreign_session_id)
    result['known_session_context_valid'] = valid_context
    if session_id is None:
        relation = 'not_present'
    elif type(session_id) is not str or not 1 <= len(session_id) <= 96:
        relation = 'invalid'
    elif not valid_context:
        relation = 'context_invalid'
    elif session_id == own_session_id:
        relation = 'own'
    elif session_id == foreign_session_id:
        relation = 'foreign'
    else:
        relation = 'other'
    result['session_id_relation'] = relation
    output = value.get('Output')
    result['output_text_present'] = type(output) is str and bool(output)
    if type(output) is str:
        folded = output.casefold()
        for key, phrase in HINTS:
            result[key] = phrase in folded
    # Output, arbitrary JSON fields and identifiers are never copied or hashed
    # into the result. A lexical hint is never an authentication/access verdict.
    return result


def _payload_json(payload, result, own_session_id, foreign_session_id):
    value = _json_object(payload, result)
    if value is None:
        return _reject(result, 'payload_json_invalid')
    if result['message_type'] == 'channel_closed':
        return _closed(value, result, own_session_id, foreign_session_id)
    if result['payload_type'] == 'handshake_request':
        actions = value.get('RequestedClientActions')
        if type(actions) is not list or len(actions) > MAX_FRAMES:
            return _reject(result, 'handshake_actions_invalid')
        result['handshake_action_count'] = len(actions)
        for action in actions:
            action_type = action.get('ActionType') if type(action) is dict else None
            if action_type == 'SessionType':
                result['handshake_session_type_actions'] += 1
            elif action_type == 'KMSEncryption':
                result['handshake_kms_actions'] += 1
            else:
                result['handshake_unknown_actions'] += 1
    elif result['payload_type'] == 'handshake_complete':
        result['handshake_complete_observed'] = True
        customer = value.get('CustomerMessage')
        result['customer_message_present'] = type(customer) is str and bool(customer)
    return result


def _binary(payload, result, own_session_id, foreign_session_id):
    if len(payload) < PAYLOAD_OFFSET:
        return _reject(result, 'binary_header_truncated')
    header_length = struct.unpack_from('>I', payload, 0)[0]
    schema = struct.unpack_from('>I', payload, 36)[0]
    length = struct.unpack_from('>I', payload, 116)[0]
    if header_length != HEADER_LENGTH:
        return _reject(result, 'binary_header_length_unknown')
    result['header_valid'] = True
    if length != len(payload) - PAYLOAD_OFFSET:
        return _reject(result, 'binary_payload_length_mismatch')
    result['length_valid'] = True
    result['payload_bytes'] = length
    if schema != 1:
        return _reject(result, 'binary_schema_unknown', 'unknown')
    result['schema_known'] = True
    body = payload[PAYLOAD_OFFSET:]
    if length:
        if not hmac.compare_digest(hashlib.sha256(body).digest(), payload[80:112]):
            result['payload_digest'] = 'invalid'
            return _reject(result, 'binary_payload_digest_invalid')
        result['payload_digest'] = 'valid'
    else:
        # The official Validate() skips payload digest verification when empty.
        result['payload_digest'] = 'not_applicable_empty'
    raw_type = payload[4:36].strip(b'\x00 \t\r\n')
    known_type = next((name for name in MESSAGE_TYPES if name.encode('ascii') == raw_type), 'unknown')
    result['message_type'] = known_type
    type_id = struct.unpack_from('>I', payload, 112)[0]
    result['payload_type'] = PAYLOAD_TYPES.get(type_id, 'unknown')
    if known_type == 'unknown':
        return _reject(result, 'binary_message_type_unknown', 'unknown')
    result['parse_status'] = 'recognized'
    result['reason'] = 'metadata_observed'
    if known_type == 'channel_closed' or (known_type == 'output_stream_data' and
            result['payload_type'] in ('handshake_request', 'handshake_complete')):
        return _payload_json(body, result, own_session_id, foreign_session_id)
    return result


def observe_frame(kind, payload, *, own_session_id=None, foreign_session_id=None):
    """Return only fixed enums, bounded counts and booleans from complete bytes.

    Unknown/malformed input produces fixed metadata, never an exception string.
    A text channel_closed object is observational only; it has no binary digest.
    No output means authorization granted/denied or protocol completed.
    """
    safe_kind = kind if type(kind) is str and kind in FRAME_KINDS else 'unknown'
    result = _empty(safe_kind)
    if type(payload) is not bytes:
        return _reject(result, 'input_must_be_bytes')
    # Check BEFORE decoding/copying/parsing. Transport allocation is caller-owned.
    if len(payload) > MAX_FRAME_BYTES:
        return _reject(result, 'frame_byte_limit', 'limit')
    result['frame_bytes'] = len(payload)
    if safe_kind == 'unknown':
        return result
    if safe_kind == 'binary':
        return _binary(payload, result, own_session_id, foreign_session_id)
    if safe_kind in ('ping', 'pong', 'close'):
        if len(payload) > 125 or (safe_kind == 'close' and len(payload) == 1):
            return _reject(result, 'control_payload_invalid')
        if safe_kind == 'close' and payload:
            code = struct.unpack_from('>H', payload, 0)[0]
            if not 1000 <= code <= 4999:
                return _reject(result, 'close_code_out_of_range')
            result['close_code'] = code
            result['close_reason_present'] = len(payload) > 2
        result['parse_status'] = 'recognized'
        result['reason'] = 'control_frame_observed'
        result['length_valid'] = True
        return result
    value = _json_object(payload, result)
    if value is None:
        return _reject(result, 'text_json_invalid')
    if value.get('MessageType') != 'channel_closed':
        return _reject(result, 'text_message_type_unknown', 'unknown')
    result['message_type'] = 'channel_closed'
    if type(value.get('SchemaVersion')) is not int or value['SchemaVersion'] != 1:
        return _reject(result, 'text_schema_unknown', 'unknown')
    result.update(schema_known=True, length_valid=True,
                  payload_digest='not_applicable_text', parse_status='recognized',
                  reason='metadata_observed')
    return _closed(value, result, own_session_id, foreign_session_id)


class MetadataObserver:
    """Bound counters supplied with elapsed monotonic milliseconds by caller.

    Retains identifiers privately and counters only, never payloads or results.
    After a limit/time regression it is permanently stopped. The caller must
    also cap fragmented frames and reassembly at transport level before feed().
    """
    def __init__(self, own_session_id, foreign_session_id=None):
        self._own = own_session_id
        self._foreign = foreign_session_id
        self._frames = 0
        self._bytes = 0
        self._elapsed = 0
        self._stop_reason = ''

    def _time(self, elapsed_ms):
        if type(elapsed_ms) is not int or elapsed_ms < self._elapsed or elapsed_ms < 0:
            self._stop_reason = self._stop_reason or 'elapsed_invalid'
        elif elapsed_ms >= MAX_ELAPSED_MS:
            self._stop_reason = self._stop_reason or 'time_limit'
        else:
            self._elapsed = elapsed_ms

    def feed(self, kind, payload, elapsed_ms):
        self._time(elapsed_ms)
        if not self._stop_reason:
            if type(kind) is not str or kind not in FRAME_KINDS:
                self._stop_reason = 'frame_kind_unsupported'
            elif type(payload) is not bytes:
                self._stop_reason = 'input_must_be_bytes'
            elif len(payload) > MAX_FRAME_BYTES:
                self._stop_reason = 'frame_byte_limit'
            elif self._frames >= MAX_FRAMES:
                self._stop_reason = 'frame_count_limit'
            elif self._bytes + len(payload) > MAX_TOTAL_BYTES:
                self._stop_reason = 'total_byte_limit'
        if self._stop_reason:
            result = _reject(_empty(), self._stop_reason, 'limit')
        else:
            self._frames += 1
            self._bytes += len(payload)
            result = observe_frame(kind, payload, own_session_id=self._own,
                                   foreign_session_id=self._foreign)
        result.update(observed_frames=self._frames, observed_bytes=self._bytes,
                      elapsed_ms=self._elapsed, stopped=bool(self._stop_reason))
        return result
