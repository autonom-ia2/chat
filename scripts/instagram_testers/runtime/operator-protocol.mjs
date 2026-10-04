/* eslint-disable no-control-regex -- Reject controls at the fixed protocol boundary. */
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const STATES = [
  'queued',
  'running',
  'operator_required',
  'succeeded',
  'failed',
];
const failure = () => new Error('publication_failed');
const exact = (value, keys) =>
  value &&
  typeof value === 'object' &&
  !Array.isArray(value) &&
  Object.keys(value).sort().join(',') === [...keys].sort().join(',');
const uuid = value => typeof value === 'string' && UUID.test(value);
export const METADATA_KEYS = [
  'INSTAGRAM_META_DEVELOPER_APP_ID',
  'INSTAGRAM_META_BUSINESS_ID',
  'INSTAGRAM_TESTER_APP_NAME',
  'INSTAGRAM_TESTER_ADMIN_USER_ID',
  'INSTAGRAM_TESTER_ROLES_DOC_ID',
];
const numeric = value =>
  typeof value === 'string' && /^[0-9]{1,40}$/.test(value);
const fingerprint = value =>
  typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const timestamp = value => {
  if (
    typeof value !== 'string' ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)
  )
    return false;
  const date = new Date(value);
  return Number.isFinite(date.getTime()) && date.toISOString() === value;
};
export function validateMetadata(value) {
  return (
    exact(value, METADATA_KEYS) &&
    METADATA_KEYS.every(key => {
      const item = value[key];
      return key === 'INSTAGRAM_TESTER_APP_NAME'
        ? typeof item === 'string' &&
            Buffer.byteLength(item) > 0 &&
            Buffer.byteLength(item) <= 480 &&
            Array.from(item).length <= 120 &&
            item.trim() === item &&
            !/[\x00-\x1f\x7f]/.test(item)
        : numeric(item);
    })
  );
}

export function validateManager(value) {
  return (
    exact(value, ['state', 'control_available', 'observed_at']) &&
    timestamp(value.observed_at) &&
    ['healthy', 'operator_required', 'failed'].includes(value.state) &&
    typeof value.control_available === 'boolean' &&
    (!value.control_available || value.state === 'operator_required')
  );
}

export function validateOperatorRequest(value) {
  return (
    exact(value, [
      'id',
      'action',
      'state',
      'actor_id',
      'created_at',
      'updated_at',
      'expires_at',
    ]) &&
    Number.isSafeInteger(value.actor_id) &&
    value.actor_id > 0 &&
    timestamp(value.updated_at) &&
    Date.parse(value.updated_at) >= Date.parse(value.created_at) &&
    timestamp(value.created_at) &&
    timestamp(value.expires_at) &&
    Date.parse(value.expires_at) > Date.parse(value.created_at) &&
    Date.parse(value.expires_at) - Date.parse(value.created_at) <= 3600000 &&
    uuid(value.id) &&
    value.action === 'reconnect' &&
    STATES.includes(value.state)
  );
}

export function parseEnvelope(output, type) {
  try {
    if (typeof output !== 'string' || Buffer.byteLength(output) > 1024)
      throw failure();
    const value = JSON.parse(output);
    if (type && value?.type !== type) throw failure();
    if (
      value?.type === 'bootstrap' &&
      exact(value, ['type', 'metadata', 'revision', 'version']) &&
      validateMetadata(value.metadata) &&
      fingerprint(value.revision) &&
      (value.version === null || uuid(value.version))
    )
      return value;
    if (
      value?.type === 'session' &&
      exact(value, ['type', 'version']) &&
      (value.version === null || uuid(value.version))
    )
      return value;
    if (
      value?.type === 'operator' &&
      exact(value, ['type', 'manager', 'request']) &&
      (value.manager === null || validateManager(value.manager)) &&
      (value.request === null || validateOperatorRequest(value.request))
    )
      return value;
    throw failure();
  } catch {
    throw failure();
  }
}

export function validateRequest(value) {
  let valid = false;
  if (value?.type === 'operator') {
    if (value.operation === 'manager_heartbeat')
      valid =
        exact(value, [
          'type',
          'operation',
          'state',
          'control_available',
          ...(Object.hasOwn(value, 'request_id') ? ['request_id'] : []),
        ]) &&
        (!Object.hasOwn(value, 'request_id') || uuid(value.request_id)) &&
        ['healthy', 'operator_required', 'failed'].includes(value.state) &&
        typeof value.control_available === 'boolean' &&
        (!value.control_available || value.state === 'operator_required');
    if (value.operation === 'operator_read')
      valid = exact(value, ['type', 'operation']);
    if (value.operation === 'operator_claim')
      valid = exact(value, ['type', 'operation', 'id']) && uuid(value.id);
    if (value.operation === 'operator_complete')
      valid =
        exact(value, ['type', 'operation', 'id', 'state']) &&
        uuid(value.id) &&
        ['operator_required', 'failed'].includes(value.state);
    valid = valid && Buffer.byteLength(JSON.stringify(value)) <= 512;
  } else if (value?.type === 'session') {
    if (['version', 'bootstrap'].includes(value.operation))
      valid = exact(value, ['type', 'operation']);
    if (value.operation === 'publish') {
      const keys = [
        'type',
        'operation',
        'session',
        'expected_version',
        'captured_at',
        'app_id',
        'business_id',
        'proxy_fingerprint',
        'roles_response',
        'configuration_revision',
        'roles_doc_id',
      ];
      if (Object.hasOwn(value, 'request_id')) keys.push('request_id');
      valid =
        exact(value, keys) &&
        fingerprint(value.configuration_revision) &&
        numeric(value.roles_doc_id) &&
        (value.expected_version === null || uuid(value.expected_version)) &&
        (!Object.hasOwn(value, 'request_id') || uuid(value.request_id)) &&
        value.session &&
        typeof value.session === 'object' &&
        !Array.isArray(value.session) &&
        [
          'captured_at',
          'app_id',
          'business_id',
          'proxy_fingerprint',
          'roles_response',
        ].every(key => typeof value[key] === 'string');
    }
    valid =
      valid && Buffer.byteLength(JSON.stringify(value)) <= 2 * 1024 * 1024;
  }
  if (!valid) throw failure();
  return value;
}
