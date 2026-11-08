import { ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import ChannelApi from 'dashboard/api/channels';
import { buildFacebookLoginScopes } from 'dashboard/helper/facebookScopes';
import { setupFacebookSdk } from 'dashboard/routes/dashboard/settings/inbox/channels/whatsapp/utils';

// Headless half of the Facebook Page connect flow: load the Meta SDK, run
// FB.login for page scopes, and fetch the user's pages. The caller owns the
// page-picker UI and the channel creation, because choosing a page is an
// interactive step (a user can manage several pages).
//
// Split into preloadSdk() + loginAndFetchPages() for popup safety: FB.login
// opens a popup and needs the click's transient activation. Preloading the SDK
// when the picker opens means the click-time `await` resolves within that
// activation window; a cold load resolves on the script's `load` task seconds
// later, after activation has expired, and the popup gets blocked.
// Without an app id the SDK starts with no app and FB.login never calls back
// (#2319): the caller would wait forever. Fail before opening the login.
export const FACEBOOK_NOT_CONFIGURED = 'FacebookNotConfigured';

const notConfiguredError = () => {
  const error = new Error('Facebook app is not configured');
  error.name = FACEBOOK_NOT_CONFIGURED;
  return error;
};

export function useFacebookPageConnect() {
  const accountId = useMapGetter('getCurrentAccountId');
  const isAuthenticating = ref(false);

  let sdkSetupPromise = null;

  // Idempotent — call this when the picker UI opens. A failed load clears the
  // cache so a later attempt can retry instead of being stuck on a rejection.
  const preloadSdk = () => {
    if (!window.chatwootConfig?.fbAppId) {
      return Promise.reject(notConfiguredError());
    }
    if (!sdkSetupPromise) {
      sdkSetupPromise = setupFacebookSdk(
        window.chatwootConfig.fbAppId,
        window.chatwootConfig?.fbApiVersion
      ).catch(error => {
        sdkSetupPromise = null;
        throw error;
      });
    }
    return sdkSetupPromise;
  };

  // FB.login never rejects; resolve the user access token on success and null
  // for any other status (closed popup, not_authorized, unknown). It runs right
  // in the click, so the popup keeps the gesture; without an app it would never
  // call back, so it refuses first.
  const login = (extraScopes = []) => {
    if (!window.chatwootConfig?.fbAppId) {
      return Promise.reject(notConfiguredError());
    }
    return new Promise(resolve => {
      window.FB.login(
        response => {
          resolve(
            response.status === 'connected'
              ? response.authResponse?.accessToken || null
              : null
          );
        },
        { scope: buildFacebookLoginScopes({ extraScopes }) }
      );
    });
  };

  // Resolves { userAccessToken, pages } on success, null when the user cancels,
  // and rejects on missing app, SDK-load or page-fetch failure (the caller maps
  // it to UI).
  const loginAndFetchPages = async () => {
    if (isAuthenticating.value) return null;
    isAuthenticating.value = true;
    try {
      await preloadSdk();
      const token = await login();
      if (!token) return null;

      const response = await ChannelApi.fetchFacebookPages(
        token,
        accountId.value
      );
      const { page_details: pages, user_access_token: userAccessToken } =
        response.data.data;
      return { userAccessToken, pages };
    } finally {
      isAuthenticating.value = false;
    }
  };

  // Reauthorizing a page that already has an inbox only needs the user token
  // (Your posts #2199 asks read_insights on top of the page scopes).
  return { isAuthenticating, preloadSdk, login, loginAndFetchPages };
}
