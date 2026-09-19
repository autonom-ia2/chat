<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxReconnectionRequired from '../../components/InboxReconnectionRequired.vue';
import whatsappChannel from 'dashboard/api/channel/whatsappChannel';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
  classifySignupEvent,
  coexistenceSignal,
  COMPLETION_RESULTS,
  SIGNUP_RESULT,
} from './utils';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
  whatsappRegistrationIncomplete: {
    type: Boolean,
    default: false,
  },
});

const { t } = useI18n();

// With the inbox's stored IDs the reauthorization needs nothing else from Meta;
// the terminal event only says whether the number is coexistence. Before 4.18.0
// this path reauthorized as soon as FB.login returned the code. Waiting on the
// event without a deadline could leave the button spinning, so it gets a short
// grace window and, past it, is_coexistence goes as null (backend falls back to
// Meta's health data).
const FINISH_GRACE_MS = 10 * 1000;

const isRequestingAuthorization = ref(false);
const isLoadingFacebook = ref(true);

const whatsappAppId = computed(() => window.chatwootConfig.whatsappAppId);
const whatsappConfigurationId = computed(
  () => window.chatwootConfig.whatsappConfigurationId
);

const actionLabel = computed(() => {
  if (props.whatsappRegistrationIncomplete) {
    return t('INBOX_MGMT.COMPLETE_REGISTRATION');
  }
  return '';
});

const description = computed(() => {
  if (props.whatsappRegistrationIncomplete) {
    return t('INBOX_MGMT.WHATSAPP_REGISTRATION_INCOMPLETE');
  }
  return '';
});

const reauthorizeWhatsApp = async params => {
  isRequestingAuthorization.value = true;

  try {
    const response = await whatsappChannel.reauthorizeWhatsApp({
      inboxId: props.inbox.id,
      ...params,
    });

    if (response.data.success) {
      useAlert(t('INBOX.REAUTHORIZE.SUCCESS'));
    } else {
      useAlert(response.data.message || t('INBOX.REAUTHORIZE.ERROR'));
    }
  } catch (error) {
    useAlert(error.message || t('INBOX.REAUTHORIZE.ERROR'));
  } finally {
    isRequestingAuthorization.value = false;
  }
};

const handleEmbeddedSignupEvents = async (data, authCode) => {
  if (!data || typeof data !== 'object') {
    return;
  }

  const result = classifySignupEvent(data);

  if (COMPLETION_RESULTS.includes(result.type)) {
    const businessData = data.data;

    // phone_number_id isn't required here: the backend resolves it from the WABA
    // (PhoneInfoService, matching the reauthorized channel's number) when omitted,
    // which coexistence and FINISH_ONLY_WABA completions do.
    if (isValidBusinessData(businessData)) {
      await reauthorizeWhatsApp({
        code: authCode,
        business_id: businessData.business_id || '',
        waba_id: businessData.waba_id,
        phone_number_id: businessData.phone_number_id || '',
        is_coexistence: coexistenceSignal(result),
      });
    } else {
      isRequestingAuthorization.value = false;
      useAlert(
        t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.INVALID_BUSINESS_DATA')
      );
    }
  } else if (result.type === SIGNUP_RESULT.CANCEL) {
    isRequestingAuthorization.value = false;
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'));
  } else if (result.type === SIGNUP_RESULT.ERROR) {
    isRequestingAuthorization.value = false;
    useAlert(
      result.errorMessage ||
        t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SIGNUP_ERROR')
    );
  }
};

// FB.login's authCode and Meta's FINISH postMessage arrive independently and in no
// guaranteed order (see useWhatsappEmbeddedSignup.js), so the listener is registered
// before the auth code is known and buffers a FINISH event until setAuthCode() runs —
// otherwise a FINISH that arrives before FB.login resolves would be missed entirely.
const startEmbeddedSignup = () => {
  let authCode = null;
  let pendingEvent = null;
  let messageHandler;
  let settled = false;

  const settle = () => {
    if (settled) return;
    settled = true;
    window.removeEventListener('message', messageHandler);
  };

  const process = () => {
    if (!authCode || !pendingEvent) return;
    settle();
    handleEmbeddedSignupEvents(pendingEvent, authCode);
  };

  messageHandler = createMessageHandler(data => {
    const { type } = classifySignupEvent(data);
    // Non-terminal payloads must not tear down the listener — the flow is still live.
    if (type === SIGNUP_RESULT.IGNORE) return;

    if (COMPLETION_RESULTS.includes(type)) {
      // Keep the first terminal event: a coexistence FINISH must win over a
      // later normal FINISH that can arrive before the auth code is known.
      pendingEvent = pendingEvent || data;
      process();
      return;
    }

    settle();
    handleEmbeddedSignupEvents(data, authCode);
  });
  window.addEventListener('message', messageHandler);

  return {
    setAuthCode: code => {
      authCode = code;
      process();
    },
    cleanup: settle,
  };
};

// The "existing config" reauth shortcut already trusts the stored business/phone IDs,
// so it only needs to know which FINISH variant occurred — same ordering guarantee as
// startEmbeddedSignup above, just without needing to buffer the event's business data.
const createFinishEventWaiter = () => {
  let listener;
  const promise = new Promise((resolve, reject) => {
    listener = createMessageHandler(data => {
      const result = classifySignupEvent(data);
      if (result.type === SIGNUP_RESULT.IGNORE) return;

      window.removeEventListener('message', listener);

      if (COMPLETION_RESULTS.includes(result.type)) {
        resolve(coexistenceSignal(result));
      } else if (result.type === SIGNUP_RESULT.CANCEL) {
        reject(
          new Error(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'))
        );
      } else {
        reject(
          new Error(
            result.errorMessage ||
              t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SIGNUP_ERROR')
          )
        );
      }
    });
    window.addEventListener('message', listener);
  });
  // A CANCEL/ERROR can reject this before FB.login returns the code; the race in
  // waitAfterCode still receives it, this only avoids an unhandled rejection.
  promise.catch(() => {});
  const cleanup = () => window.removeEventListener('message', listener);

  // Called once FB.login has returned the code. Resolves with the coexistence
  // signal if Meta's terminal event arrives within FINISH_GRACE_MS, else null.
  const waitAfterCode = () => {
    let timer;
    const grace = new Promise(resolve => {
      timer = setTimeout(() => resolve(null), FINISH_GRACE_MS);
    });
    return Promise.race([promise, grace]).finally(() => {
      clearTimeout(timer);
      cleanup();
    });
  };

  return { waitAfterCode, cleanup };
};

const handleLoginAndReauthorize = async () => {
  // Validate required configuration
  if (!whatsappAppId.value) {
    throw new Error('WhatsApp App ID is required');
  }
  if (!whatsappConfigurationId.value) {
    throw new Error('WhatsApp Configuration ID is required');
  }

  // Check if this is a reauthorization scenario where we already have the business data
  const existingConfig = props.inbox.provider_config;
  const hasExistingConfig = Boolean(
    existingConfig &&
      existingConfig.business_account_id &&
      existingConfig.phone_number_id
  );
  const finishWaiter = hasExistingConfig ? createFinishEventWaiter() : null;
  const embeddedSignup = hasExistingConfig ? null : startEmbeddedSignup();

  try {
    const authCode = await initWhatsAppEmbeddedSignup(
      whatsappConfigurationId.value
    );

    if (hasExistingConfig) {
      const isCoexistence = await finishWaiter.waitAfterCode();
      await reauthorizeWhatsApp({
        code: authCode,
        business_id: existingConfig.business_account_id,
        waba_id: existingConfig.business_account_id,
        phone_number_id: existingConfig.phone_number_id,
        is_coexistence: isCoexistence,
      });
      return false;
    }

    embeddedSignup.setAuthCode(authCode);
    // Still pending: the FINISH/CANCEL/error postMessage resolves asynchronously
    // and owns resetting isRequestingAuthorization from there.
    return true;
  } catch (error) {
    finishWaiter?.cleanup();
    embeddedSignup?.cleanup();
    if (error.message === 'Login cancelled') {
      useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'));
    } else {
      useAlert(
        error.message ||
          t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.AUTH_NOT_COMPLETED')
      );
    }
    return false;
  }
};

const requestAuthorization = async () => {
  if (isLoadingFacebook.value) {
    useAlert(t('INBOX.REAUTHORIZE.LOADING_FACEBOOK'));
    return;
  }

  isRequestingAuthorization.value = true;
  try {
    const stillPending = await handleLoginAndReauthorize();
    if (!stillPending) {
      isRequestingAuthorization.value = false;
    }
  } catch (error) {
    useAlert(error.message || t('INBOX.REAUTHORIZE.CONFIGURATION_ERROR'));
    isRequestingAuthorization.value = false;
  }
};

onMounted(async () => {
  try {
    // Validate required configuration
    if (!whatsappAppId.value) {
      useAlert(t('INBOX.REAUTHORIZE.WHATSAPP_APP_ID_MISSING'));
      return;
    }
    if (!whatsappConfigurationId.value) {
      useAlert(t('INBOX.REAUTHORIZE.WHATSAPP_CONFIG_ID_MISSING'));
      return;
    }

    // Load Facebook SDK and initialize
    await setupFacebookSdk(
      whatsappAppId.value,
      window.chatwootConfig?.whatsappApiVersion
    );
  } catch (error) {
    useAlert(t('INBOX.REAUTHORIZE.FACEBOOK_LOAD_ERROR'));
  } finally {
    isLoadingFacebook.value = false;
  }
});

// Expose requestAuthorization function for parent components
defineExpose({
  requestAuthorization,
});
</script>

<template>
  <InboxReconnectionRequired
    class="mx-6"
    :is-loading="isRequestingAuthorization"
    :action-label="actionLabel"
    :description="description"
    @reauthorize="requestAuthorization"
  />
</template>
