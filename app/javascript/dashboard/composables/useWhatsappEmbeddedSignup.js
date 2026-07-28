import { ref } from 'vue';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
} from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

// Drives Meta's WhatsApp embedded-signup popup (Facebook JS SDK). FB.login()
// resolves an auth `code` while the WABA identifiers (waba_id, phone_number_id)
// arrive separately over a postMessage event — order isn't guaranteed, so we
// hold both and resolve once both are present.
//
// `runEmbeddedSignup` returns the signup credentials; the caller exchanges them
// for an inbox via `inboxes/createWhatsAppEmbeddedSignup` and owns its own UX
// (alerts, navigation, etc). Resolves `null` when the user cancels the popup;
// rejects on SDK load or signup errors. The window listener is scoped to a
// single run, so this is safe to call from anywhere without lifecycle wiring.
// Meta signals a completed signup with a different event per flow. Only FINISH
// and FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING were handled, so a customer who
// finished through any other flow left the promise pending forever — no inbox,
// no error, just a spinner. The full list is in Meta's Embedded Signup
// implementation docs.
const COMPLETION_EVENTS = [
  'FINISH', // Cloud API
  'FINISH_ONLY_WABA', // finished without attaching a phone number
  'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING', // Coexistence
  'FINISH_OBO_MIGRATION', // on-behalf-of migration
  'FINISH_GRANT_ONLY_API_ACCESS', // grant-only API access
];

// Meta closes its popup without any event in some failure modes. Without a
// deadline the caller spins indefinitely with no way to tell the user why.
const SIGNUP_TIMEOUT_MS = 5 * 60 * 1000;

export function useWhatsappEmbeddedSignup() {
  const isAuthenticating = ref(false);

  const runEmbeddedSignup = () => {
    if (isAuthenticating.value) return Promise.resolve(null);
    isAuthenticating.value = true;

    return new Promise((resolve, reject) => {
      let authCode = null;
      let businessData = null;
      let settled = false;
      let messageHandler;
      let lastEvent = null;

      let timeoutId;

      const settle = (fn, value) => {
        if (settled) return;
        settled = true;
        clearTimeout(timeoutId);
        window.removeEventListener('message', messageHandler);
        isAuthenticating.value = false;
        fn(value);
      };

      timeoutId = setTimeout(() => {
        // Name what is missing: this is the difference between a silent hang
        // and an actionable report from whoever hit it.
        const missing = [
          authCode ? null : 'auth code',
          businessData ? null : 'business data',
        ]
          .filter(Boolean)
          .join(' and ');
        settle(
          reject,
          new Error(
            `WhatsApp signup timed out waiting for ${missing} (last event: ${lastEvent || 'none'})`
          )
        );
      }, SIGNUP_TIMEOUT_MS);

      // Both the auth code and the business data arrive asynchronously and in
      // no fixed order; only resolve once we're holding both.
      const resolveIfReady = () => {
        if (!authCode || !businessData) return;
        settle(resolve, {
          code: authCode,
          business_id: businessData.business_id,
          waba_id: businessData.waba_id,
          phone_number_id: businessData.phone_number_id || '',
        });
      };

      messageHandler = createMessageHandler(data => {
        lastEvent = data.event;
        if (COMPLETION_EVENTS.includes(data.event)) {
          if (!isValidBusinessData(data.data)) {
            settle(reject, new Error('Invalid business data'));
            return;
          }
          businessData = data.data;
          resolveIfReady();
        } else if (data.event === 'CANCEL') {
          settle(resolve, null);
        } else if (data.event === 'error') {
          settle(reject, new Error(data.error_message || 'Signup error'));
        }
      });

      window.addEventListener('message', messageHandler);

      (async () => {
        try {
          await setupFacebookSdk(
            window.chatwootConfig?.whatsappAppId,
            window.chatwootConfig?.whatsappApiVersion
          );
          authCode = await initWhatsAppEmbeddedSignup(
            window.chatwootConfig?.whatsappConfigurationId
          );
          resolveIfReady();
        } catch (error) {
          // FB.login() rejects with 'Login cancelled' when the user dismisses
          // the popup — treat it as a cancel rather than an error.
          if (error.message === 'Login cancelled') {
            settle(resolve, null);
          } else {
            settle(reject, error);
          }
        }
      })();
    });
  };

  return { isAuthenticating, runEmbeddedSignup };
}
