import { loadScript } from 'dashboard/helper/DOMHelpers';

export const loadFacebookSdk = async () => {
  return loadScript('https://connect.facebook.net/en_US/sdk.js', {
    async: true,
    defer: true,
    crossOrigin: 'anonymous',
  });
};

export const initializeFacebook = (appId, apiVersion) => {
  const version = apiVersion || 'v22.0';
  return new Promise(resolve => {
    const init = () => {
      window.FB.init({
        appId,
        autoLogAppEvents: true,
        xfbml: true,
        version,
      });
      resolve();
    };

    if (window.FB) {
      init();
    } else {
      window.fbAsyncInit = init;
    }
  });
};

// `waba_id` is the only identifier Meta guarantees across every completion
// event. FINISH_ONLY_WABA in particular arrives without a phone number, and
// `business_id` is absent in some Coexistence payloads — requiring either of
// them rejected valid signups as "Invalid business data".
export const isValidBusinessData = businessData => {
  return Boolean(businessData && businessData.waba_id);
};

export const createMessageHandler = onEmbeddedSignupData => {
  return event => {
    if (!event.origin.endsWith('facebook.com')) return;

    try {
      let data;
      if (typeof event.data === 'string') {
        data = JSON.parse(event.data);
      } else if (typeof event.data === 'object' && event.data !== null) {
        data = event.data;
      } else {
        return;
      }

      if (data.type === 'WA_EMBEDDED_SIGNUP') {
        onEmbeddedSignupData(data);
      }
    } catch {
      // Ignore non-JSON or irrelevant messages
    }
  };
};

export const initWhatsAppEmbeddedSignup = configId => {
  return new Promise((resolve, reject) => {
    window.FB.login(
      response => {
        if (response.authResponse && response.authResponse.code) {
          resolve(response.authResponse.code);
        } else if (response.error) {
          reject(new Error(response.error));
        } else {
          reject(new Error('Login cancelled'));
        }
      },
      {
        config_id: configId,
        response_type: 'code',
        override_default_response_type: true,
        extras: {
          setup: {},
          // Do NOT drop `featureType`: it selects Meta's Coexistence flow,
          // which is what makes the WhatsApp Business app's message history
          // importable. Whatsapp::EmbeddedSignupService fires
          // HistorySyncService right after the channel is created, and Meta
          // only honours that within a 24h window opened by this flow.
          featureType: 'whatsapp_business_app_onboarding',
          sessionInfoVersion: '3',
        },
      }
    );
  });
};

export const setupFacebookSdk = async (appId, apiVersion) => {
  const version = apiVersion || 'v22.0';
  await loadFacebookSdk();
  await initializeFacebook(appId, version);
};
