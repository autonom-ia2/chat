<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { useBranding } from 'shared/composables/useBranding';
import oauthAPI from 'dashboard/api/oauth';
import {
  OAUTH_AUTHORIZE_PARAMS,
  OAUTH_SCOPE_LABELS,
} from 'dashboard/constants/oauth';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const route = useRoute();
const { t } = useI18n();
const { replaceInstallationName } = useBranding();
const currentUser = useMapGetter('getCurrentUser');

const authorization = ref(null);
// No answer at all (offline) is told apart from a request the server refused
const hasNetworkError = ref(false);
const isLoading = ref(true);
const isSubmitting = ref(false);
// Only administrators may connect apps (#3089), so only the accounts the user administers are offered.
const adminAccounts = computed(() =>
  (currentUser.value.accounts || []).filter(
    account => account.role === 'administrator' && account.status === 'active'
  )
);
const routeAccountId = Number(route.params.accountId);
const selectedAccountId = ref(
  adminAccounts.value.some(account => account.id === routeAccountId)
    ? routeAccountId
    : (adminAccounts.value[0]?.id ?? null)
);

const oauthParams = computed(() =>
  Object.fromEntries(
    OAUTH_AUTHORIZE_PARAMS.filter(param => route.query[param]).map(param => [
      param,
      route.query[param],
    ])
  )
);

const accountOptions = computed(() =>
  adminAccounts.value.map(account => ({
    value: account.id,
    label: account.name,
  }))
);

const scopes = computed(() =>
  authorization.value.scope
    .split(' ')
    .filter(scope => OAUTH_SCOPE_LABELS[scope])
);

const singleAccountName = computed(() =>
  accountOptions.value.length === 1 ? accountOptions.value[0].label : ''
);

const redirectHost = computed(
  () => new URL(authorization.value.redirect_uri).host
);

const fetchAuthorization = async () => {
  isLoading.value = true;
  hasNetworkError.value = false;
  try {
    const { data } = await oauthAPI.getAuthorization(oauthParams.value);
    authorization.value = data;
  } catch (error) {
    hasNetworkError.value = !error.response;
  } finally {
    isLoading.value = false;
  }
};

// The client finishes the flow, so both answers end by sending the browser back to it
const respond = async request => {
  isSubmitting.value = true;
  try {
    const { data } = await request;
    window.location.assign(data.redirect_uri);
  } catch (error) {
    authorization.value = null;
    hasNetworkError.value = !error.response;
    isSubmitting.value = false;
  }
};

const approve = () =>
  respond(
    oauthAPI.approveAuthorization({
      ...oauthParams.value,
      account_id: selectedAccountId.value,
    })
  );

const deny = () => respond(oauthAPI.denyAuthorization(oauthParams.value));

const goToDashboard = () => window.location.assign('/app');

onMounted(fetchAuthorization);
</script>

<template>
  <div
    class="flex min-h-screen items-center justify-center bg-n-background p-4 sm:p-6"
  >
    <div
      class="flex w-full max-w-lg flex-col gap-6 rounded-xl border border-n-weak bg-n-solid-1 p-6 shadow"
    >
      <div
        v-if="isLoading"
        class="flex justify-center text-n-slate-11"
        role="status"
        aria-live="polite"
      >
        <Spinner />
      </div>
      <div
        v-else-if="authorization && !accountOptions.length"
        class="flex flex-col gap-4"
      >
        <h1 class="text-heading-2 text-n-slate-12">
          {{ t('OAUTH.AUTHORIZE.NO_ADMIN_TITLE') }}
        </h1>
        <p class="text-body-main text-n-slate-11">
          {{ t('OAUTH.AUTHORIZE.NO_ADMIN_ACCOUNT') }}
        </p>
        <Button
          lg
          class="w-full sm:w-auto sm:self-end"
          :label="t('OAUTH.AUTHORIZE.BACK_TO_APP')"
          :disabled="isSubmitting"
          :is-loading="isSubmitting"
          @click="deny"
        />
      </div>
      <template v-else-if="authorization">
        <div class="flex flex-col gap-2">
          <h1 class="text-heading-2 text-n-slate-12">
            {{
              replaceInstallationName(
                t('OAUTH.AUTHORIZE.TITLE', {
                  appName: authorization.client_name,
                })
              )
            }}
          </h1>
          <p class="text-body-main text-n-slate-11">
            {{
              t('OAUTH.AUTHORIZE.DESCRIPTION', {
                appName: authorization.client_name,
              })
            }}
          </p>
        </div>
        <ul class="flex flex-col gap-3">
          <li
            v-for="scope in scopes"
            :key="scope"
            class="flex items-start gap-2 text-body-main text-n-slate-12"
          >
            <Icon
              icon="i-lucide-check"
              class="mt-0.5 size-4 flex-shrink-0 text-n-teal-11"
            />
            {{ t(OAUTH_SCOPE_LABELS[scope]) }}
          </li>
        </ul>
        <!-- The name is chosen by whoever registered the app; the address is what really gets the access -->
        <div
          class="flex items-start gap-2 rounded-lg bg-n-amber-3 p-3 text-body-main text-n-slate-12"
        >
          <Icon
            icon="i-lucide-shield-alert"
            class="mt-0.5 size-4 flex-shrink-0 text-n-amber-11"
          />
          <p class="flex flex-col gap-1">
            <span>{{ t('OAUTH.AUTHORIZE.REDIRECT_LABEL') }}</span>
            <strong class="break-all">{{ redirectHost }}</strong>
            <span>{{ t('OAUTH.AUTHORIZE.REDIRECT_HINT') }}</span>
          </p>
        </div>
        <p v-if="singleAccountName" class="text-body-main text-n-slate-12">
          {{ t('OAUTH.AUTHORIZE.ACCOUNT_SINGLE', { name: singleAccountName }) }}
        </p>
        <div v-else class="flex flex-col gap-2">
          <span class="text-body-main font-medium text-n-slate-12">
            {{ t('OAUTH.AUTHORIZE.ACCOUNT_LABEL') }}
          </span>
          <ChoiceSelect
            v-model="selectedAccountId"
            :options="accountOptions"
            :aria-label="t('OAUTH.AUTHORIZE.ACCOUNT_LABEL')"
          />
          <span class="text-body-b3 text-n-slate-11">
            {{ t('OAUTH.AUTHORIZE.ACCOUNT_NOTE') }}
          </span>
        </div>
        <div class="flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
          <Button
            lg
            faded
            slate
            class="w-full sm:w-auto"
            :label="t('OAUTH.AUTHORIZE.DENY')"
            :disabled="isSubmitting"
            @click="deny"
          />
          <Button
            lg
            class="w-full sm:w-auto"
            :label="t('OAUTH.AUTHORIZE.ALLOW')"
            :disabled="isSubmitting || !selectedAccountId"
            :is-loading="isSubmitting"
            @click="approve"
          />
        </div>
      </template>
      <div v-else-if="hasNetworkError" class="flex flex-col gap-4">
        <h1 class="text-heading-2 text-n-slate-12">
          {{ t('OAUTH.AUTHORIZE.NETWORK_ERROR_TITLE') }}
        </h1>
        <p class="text-body-main text-n-slate-11">
          {{ t('OAUTH.AUTHORIZE.NETWORK_ERROR_DESCRIPTION') }}
        </p>
        <Button
          lg
          class="w-full sm:w-auto sm:self-end"
          :label="t('OAUTH.AUTHORIZE.RETRY')"
          @click="fetchAuthorization"
        />
      </div>
      <div v-else class="flex flex-col gap-4">
        <h1 class="text-heading-2 text-n-slate-12">
          {{ t('OAUTH.AUTHORIZE.ERROR_TITLE') }}
        </h1>
        <p class="text-body-main text-n-slate-11">
          {{ t('OAUTH.AUTHORIZE.ERROR_DESCRIPTION') }}
        </p>
        <Button
          lg
          class="w-full sm:w-auto sm:self-end"
          :label="replaceInstallationName(t('OAUTH.AUTHORIZE.GO_TO_DASHBOARD'))"
          @click="goToDashboard"
        />
      </div>
    </div>
  </div>
</template>
