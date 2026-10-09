import { computed, ref, watch } from 'vue';
import instagramClient from 'dashboard/api/channel/instagramClient';
import { useAbortableRequest } from './useAbortableRequest';

export const INSTAGRAM_ACCEPTANCE_URL =
  'https://www.instagram.com/accounts/manage_access/';
const VALID_STATUSES = ['absent', 'pending', 'accepted'];
// Accepted still needs the status op: it issues the authorization attestation.
const SEARCH_STATUSES = ['absent', 'pending'];
const USERNAME_CHARACTERS =
  'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._';

export const normalizeInstagramUsername = value => {
  const trimmed = value.trim().toLowerCase();
  return trimmed.startsWith('@') ? trimmed.slice(1) : trimmed;
};
export const isInstagramUsername = value =>
  value.length > 0 &&
  value.length <= 30 &&
  [...value].every(character => USERNAME_CHARACTERS.includes(character));

export function useInstagramTester({ disabled, returnTo }) {
  const request = useAbortableRequest();
  const configuration = ref(null);
  const username = ref('');
  const results = ref([]);
  const searched = ref(false);
  const selected = ref(null);
  const status = ref(null);
  const authorizationAttestation = ref(null);
  const operation = ref('');
  const error = ref('');
  const notice = ref('');
  const sent = ref(false);
  const needsReconciliation = ref(false);
  // Selection tokens whose search status was already shown once. Any later
  // selection reads Meta again, so a stale search status is never reused.
  let consumedSearchStatus = new Set();
  const available = computed(
    () => configuration.value?.enabled && configuration.value?.available
  );
  const busy = computed(() => request.isPending.value);
  const titleKey = computed(() => {
    if (!selected.value) return 'RESULTS_TITLE';
    if (status.value === 'accepted') return 'CONFIRMED_TITLE';
    if (status.value === 'pending')
      return sent.value ? 'SENT_TITLE' : 'PENDING_TITLE';
    if (status.value === 'absent' && !needsReconciliation.value)
      return 'ABSENT_TITLE';
    return busy.value ? 'CHECKING' : 'CHECK_INVITE';
  });

  const changeProfile = () => {
    if (busy.value && operation.value === 'invite') return;
    request.abort();
    selected.value = null;
    status.value = null;
    authorizationAttestation.value = null;
    error.value = '';
    notice.value = '';
    sent.value = false;
    needsReconciliation.value = false;
  };

  watch(
    username,
    () => {
      changeProfile();
      results.value = [];
      searched.value = false;
    },
    { flush: 'sync' }
  );

  const handleError = (failure, action) => {
    const code = failure?.response?.data?.error_code;
    const messages = {
      invalid_username: 'INVALID_USERNAME',
      invalid_selection: 'INVALID_SELECTION',
      meta_unavailable: 'UNAVAILABLE',
      meta_session_expired: 'UNAVAILABLE',
      proxy_unavailable: 'UNAVAILABLE',
      unknown_status: 'STATUS_ERROR',
      invite_rejected: 'INVITE_ERROR',
      invite_unknown: 'INVITE_UNKNOWN',
      invite_not_sent: 'INVITE_NOT_SENT',
      rate_limited: 'RATE_LIMITED',
      forbidden: 'UNAVAILABLE',
      not_enabled: 'UNAVAILABLE',
      busy: 'BUSY',
    };
    error.value =
      (Object.hasOwn(messages, code) ? messages[code] : null) ||
      (action === 'configuration'
        ? 'UNAVAILABLE'
        : `${action.toUpperCase()}_ERROR`);
    if (code === 'invalid_selection') {
      changeProfile();
      results.value = [];
      searched.value = false;
      error.value = 'INVALID_SELECTION';
    }
    // Rails reports invite_not_sent only after proving nothing reached Meta,
    // so the profile stays absent and Invite stays available.
    if (action === 'invite' && code !== 'invite_not_sent') {
      needsReconciliation.value = true;
      status.value = null;
      if (!code || code === 'invite_unknown') error.value = 'INVITE_UNKNOWN';
    }
    if (
      action === 'oauth' ||
      (action === 'status' && status.value !== 'pending')
    ) {
      status.value = null;
      authorizationAttestation.value = null;
    }
  };

  const run = async (action, callback, apply) => {
    if (busy.value) return;
    operation.value = action;
    error.value = '';
    notice.value = '';
    try {
      const response = await request.run(callback);
      if (response) apply(response.data);
    } catch (failure) {
      handleError(failure, action);
    }
  };

  const loadConfiguration = () =>
    run(
      'configuration',
      signal => instagramClient.getTesterConfiguration({ signal }),
      data => {
        if (
          data.enabled !== true ||
          data.available !== true ||
          typeof data.app_name !== 'string' ||
          !data.app_name.trim() ||
          data.acceptance_url !== INSTAGRAM_ACCEPTANCE_URL
        ) {
          configuration.value = null;
          error.value = 'UNAVAILABLE';
          return;
        }
        configuration.value = data;
      }
    );

  const search = () => {
    if (busy.value || disabled.value || !available.value) return undefined;
    const normalized = normalizeInstagramUsername(username.value);
    if (!isInstagramUsername(normalized)) {
      error.value = 'INVALID_USERNAME';
      return undefined;
    }
    results.value = [];
    searched.value = false;
    consumedSearchStatus = new Set();
    return run(
      'search',
      signal => instagramClient.searchTesters(normalized, { signal }),
      data => {
        if (
          !Array.isArray(data.results) ||
          !data.results.every(
            result =>
              typeof result.id === 'string' &&
              typeof result.username === 'string' &&
              typeof result.name === 'string' &&
              typeof result.selection_token === 'string' &&
              result.selection_token &&
              isInstagramUsername(result.username)
          )
        ) {
          error.value = 'SEARCH_ERROR';
          return;
        }
        results.value = data.results.map(result =>
          [undefined, null, ...VALID_STATUSES].includes(result.tester_status)
            ? result
            : { ...result, tester_status: null }
        );
        searched.value = true;
      }
    );
  };

  const readStatus = ({ afterUnknownInvite }) => {
    if (busy.value || disabled.value || !selected.value || !available.value)
      return undefined;
    const token = selected.value.selection_token;
    const wasPending = status.value === 'pending';
    authorizationAttestation.value = null;
    return run(
      'status',
      signal => instagramClient.getTesterStatus(token, { signal }),
      data => {
        if (!VALID_STATUSES.includes(data.status)) {
          if (status.value !== 'pending') status.value = null;
          error.value = 'STATUS_ERROR';
          return;
        }
        if (afterUnknownInvite && data.status === 'absent') {
          // Meta may list a sent invite late; never re-expose Invite here.
          status.value = null;
          needsReconciliation.value = true;
          error.value = 'INVITE_UNKNOWN';
          return;
        }
        status.value = data.status;
        authorizationAttestation.value =
          data.status === 'accepted' &&
          typeof data.authorization_attestation === 'string'
            ? data.authorization_attestation
            : null;
        needsReconciliation.value = false;
        if (data.status === 'pending' && wasPending)
          notice.value = 'STILL_PENDING';
      }
    );
  };
  const checkStatus = () => readStatus({ afterUnknownInvite: false });

  const selectProfile = candidate => {
    if (busy.value || disabled.value || !results.value.includes(candidate))
      return undefined;
    selected.value = candidate;
    sent.value = false;
    const token = candidate.selection_token;
    if (
      SEARCH_STATUSES.includes(candidate.tester_status) &&
      !consumedSearchStatus.has(token)
    ) {
      consumedSearchStatus.add(token);
      status.value = candidate.tester_status;
      authorizationAttestation.value = null;
      needsReconciliation.value = false;
      error.value = '';
      notice.value = '';
      return undefined;
    }
    status.value = null;
    return checkStatus();
  };

  const invite = async () => {
    if (
      busy.value ||
      disabled.value ||
      !available.value ||
      !selected.value ||
      status.value !== 'absent' ||
      needsReconciliation.value
    )
      return;
    await run(
      'invite',
      signal =>
        instagramClient.inviteTester(selected.value.selection_token, {
          signal,
        }),
      data => {
        if (
          !['pending', 'accepted'].includes(data.status) ||
          typeof data.invited !== 'boolean'
        ) {
          status.value = null;
          needsReconciliation.value = true;
          error.value = 'INVITE_UNKNOWN';
          return;
        }
        status.value = data.status;
        authorizationAttestation.value =
          data.status === 'accepted' &&
          typeof data.authorization_attestation === 'string'
            ? data.authorization_attestation
            : null;
        sent.value = data.invited;
      }
    );
    // One automatic check, never a loop: the status op reconciles the marker.
    if (error.value !== 'INVITE_UNKNOWN') return;
    await readStatus({ afterUnknownInvite: true });
    // A failed check proves nothing: the invite may still have reached Meta.
    if (needsReconciliation.value && status.value === null)
      error.value = 'INVITE_UNKNOWN';
  };

  const authorize = () => {
    if (
      busy.value ||
      disabled.value ||
      !available.value ||
      !selected.value ||
      status.value !== 'accepted'
    )
      return undefined;
    return run(
      'oauth',
      signal =>
        instagramClient.generateAuthorization(
          {
            tester_selection_token: selected.value.selection_token,
            ...(authorizationAttestation.value
              ? {
                  tester_authorization_attestation:
                    authorizationAttestation.value,
                }
              : {}),
            ...(returnTo?.value ? { return_to: returnTo.value } : {}),
          },
          { signal }
        ),
      data => {
        window.location.href = data.url;
      }
    );
  };

  return {
    configuration,
    username,
    results,
    searched,
    selected,
    status,
    operation,
    error,
    notice,
    busy,
    available,
    titleKey,
    needsReconciliation,
    loadConfiguration,
    search,
    selectProfile,
    changeProfile,
    checkStatus,
    invite,
    authorize,
  };
}
