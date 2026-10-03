<script setup>
import { computed, nextTick, onMounted, ref, toRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useInstagramTester } from 'dashboard/composables/useInstagramTester';
import TesterAcceptanceInstructions from './TesterAcceptanceInstructions.vue';
import { META_RESTRICTION_STATUS_URL } from 'dashboard/constants/globals';

const props = defineProps({
  disabled: { type: Boolean, default: false },
  accountId: { type: Number, required: true },
  oauthError: { type: Boolean, default: false },
});
const emit = defineEmits(['legacy']);
const { t } = useI18n();
const copy = (key, values) =>
  t(`INBOX_MGMT.ADD.INSTAGRAM.TESTER.${key}`, values);
const {
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
} = useInstagramTester({
  disabled: toRef(props, 'disabled'),
  onLegacy: () => emit('legacy'),
});
const title = ref(null);
const input = ref(null);
const parameters = computed(() => ({
  username: selected.value?.username,
  appName: configuration.value?.app_name,
}));
const errorMessage = computed(() => (error.value ? copy(error.value) : ''));
const loadingMessage = computed(() => {
  const keys = {
    configuration: 'CONFIGURING',
    search: 'SEARCHING',
    status: 'CHECKING',
    invite: 'INVITING',
    oauth: 'AUTHORIZING',
  };
  return busy.value ? copy(keys[operation.value]) : '';
});
watch([selected, status, searched], async ([profile], [previousProfile]) => {
  await nextTick();
  if (!profile && previousProfile) {
    input.value?.$el.querySelector('input')?.focus();
  } else {
    title.value?.focus();
  }
});
watch(error, async value => {
  if (value === 'INVALID_SELECTION') {
    await nextTick();
    input.value?.$el.querySelector('input')?.focus();
  }
});
onMounted(loadConfiguration);
</script>

<template>
  <section class="w-full min-w-0 p-4 sm:p-6" :aria-busy="busy">
    <div
      class="flex flex-col w-full max-w-xl gap-6 mx-auto text-start text-n-slate-12"
    >
      <header class="flex flex-col gap-2">
        <div class="flex items-center gap-3">
          <Icon
            icon="i-ri-instagram-line"
            class="size-6 shrink-0"
            aria-hidden="true"
          />
          <h1 class="m-0 text-heading-1">{{ copy('TITLE') }}</h1>
        </div>
        <p class="m-0 text-body-main text-n-slate-11">{{ copy('INTRO') }}</p>
      </header>

      <Banner v-if="disabled" color="amber" role="status">
        {{ t('INBOX_MGMT.ADD.INSTAGRAM.RESTRICTED_WARNING') }}
        <a
          :href="META_RESTRICTION_STATUS_URL"
          target="_blank"
          rel="noopener noreferrer nofollow"
          class="inline-flex min-h-11 items-center underline text-n-slate-12"
        >
          {{ t('INBOX_MGMT.ADD.INSTAGRAM.STATUS_LINK') }}
        </a>
      </Banner>
      <Banner v-if="oauthError" color="ruby" role="alert">
        {{ copy('OAUTH_ERROR') }}
      </Banner>
      <p class="sr-only" aria-live="polite" aria-atomic="true">
        {{ loadingMessage }}
      </p>

      <template v-if="available">
        <form
          v-if="!selected"
          class="flex flex-col gap-3"
          @submit.prevent="search"
        >
          <div class="flex flex-col gap-3 sm:flex-row sm:items-end">
            <Input
              id="instagram-tester-username"
              ref="input"
              v-model="username"
              class="flex-1"
              :label="copy('USERNAME_LABEL')"
              :placeholder="copy('USERNAME_PLACEHOLDER')"
              custom-input-class="!h-12 !min-h-12 !text-base"
              autocomplete="off"
              autocapitalize="none"
              :spellcheck="false"
              :aria-invalid="error === 'INVALID_USERNAME'"
              :aria-describedby="
                error === 'INVALID_USERNAME'
                  ? 'instagram-username-help instagram-tester-error'
                  : 'instagram-username-help'
              "
            />
            <Button
              type="submit"
              size="lg"
              class="w-full sm:w-auto !h-auto min-h-12 py-3 !bg-n-blue-11 dark:!bg-n-blue-8 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:ring-2 focus-visible:ring-n-brand"
              :disabled="busy"
              :is-loading="busy && operation === 'search'"
            >
              <span class="whitespace-normal">{{
                copy(busy && operation === 'search' ? 'SEARCHING' : 'SEARCH')
              }}</span>
            </Button>
          </div>
          <p
            id="instagram-username-help"
            class="m-0 text-label-small text-n-slate-11"
          >
            {{ copy('USERNAME_HELP') }}
          </p>
        </form>

        <div v-if="!selected && searched" class="flex flex-col gap-3">
          <h2 ref="title" tabindex="-1" class="m-0 text-heading-2">
            {{ copy('RESULTS_TITLE') }}
          </h2>
          <p class="m-0 text-body-main text-n-slate-11">
            {{ copy(results.length ? 'RESULTS_HELP' : 'EMPTY') }}
          </p>
          <ul
            v-if="results.length"
            class="p-0 m-0 list-none divide-y divide-n-weak"
          >
            <li v-for="candidate in results" :key="candidate.selection_token">
              <button
                type="button"
                :disabled="busy"
                :aria-label="copy('SELECT_PROFILE', candidate)"
                class="flex items-center w-full min-h-16 gap-3 p-3 text-start rounded-lg hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
                @click="selectProfile(candidate)"
              >
                <Avatar
                  :src="candidate.avatar_url || ''"
                  :name="candidate.name || candidate.username"
                  :size="40"
                  rounded-full
                  aria-hidden="true"
                />
                <span class="flex flex-col flex-1 min-w-0 gap-1">
                  <span class="text-heading-3 break-all">{{
                    copy('PROFILE_HANDLE', candidate)
                  }}</span>
                  <span class="text-body-main text-n-slate-11 break-words">{{
                    candidate.name
                  }}</span>
                </span>
                <Icon
                  icon="i-lucide-arrow-right"
                  class="size-4 shrink-0"
                  aria-hidden="true"
                />
              </button>
            </li>
          </ul>
        </div>

        <template v-if="selected">
          <div
            class="flex flex-col items-start gap-3 sm:flex-row sm:items-center"
          >
            <div class="flex w-full min-w-0 flex-1 items-center gap-3">
              <Avatar
                :src="selected.avatar_url || ''"
                :name="selected.name || selected.username"
                :size="40"
                rounded-full
                aria-hidden="true"
              />
              <div class="flex flex-col flex-1 min-w-0 gap-1">
                <span class="text-heading-3 break-all">{{
                  copy('PROFILE_HANDLE', selected)
                }}</span>
                <span class="text-body-main text-n-slate-11 break-words">{{
                  selected.name
                }}</span>
              </div>
            </div>
            <Button
              type="button"
              variant="ghost"
              color="slate"
              size="lg"
              :disabled="busy && operation === 'invite'"
              class="!h-auto min-h-12 py-3 focus-visible:ring-2 focus-visible:ring-n-brand"
              @click="changeProfile"
            >
              <span class="whitespace-normal">{{
                copy('CHANGE_PROFILE')
              }}</span>
            </Button>
          </div>
          <div class="flex flex-col gap-3">
            <h2
              ref="title"
              tabindex="-1"
              class="m-0 text-heading-2"
              :class="
                status === 'accepted'
                  ? 'text-n-teal-12 dark:text-n-teal-11'
                  : ''
              "
            >
              {{ copy(titleKey) }}
            </h2>
            <p
              v-if="status === 'absent' && !needsReconciliation"
              class="m-0 text-body-main"
            >
              {{ copy('ABSENT_HELP', parameters) }}
            </p>
            <TesterAcceptanceInstructions
              v-if="status === 'pending' || needsReconciliation"
              :username="selected.username"
              :app-name="configuration.app_name"
            />
            <p v-if="status === 'accepted'" class="m-0 text-body-main">
              {{ copy('CONFIRMED_HELP', parameters) }}
            </p>
          </div>
        </template>
      </template>

      <Banner
        v-if="errorMessage"
        id="instagram-tester-error"
        :color="error === 'INVITE_UNKNOWN' ? 'amber' : 'ruby'"
        role="alert"
      >
        {{ errorMessage }}
      </Banner>
      <p v-if="!available && !busy" class="m-0 text-body-main text-n-slate-11">
        {{ copy('MANUAL_HELP') }}
      </p>
      <p v-if="notice" class="m-0 text-body-main" aria-live="polite">
        {{ copy(notice, parameters) }}
      </p>

      <div class="flex flex-col gap-3 sm:items-start">
        <Button
          v-if="!available"
          size="lg"
          :disabled="busy"
          :is-loading="busy"
          class="w-full sm:w-auto !h-auto min-h-12 py-3 !bg-n-blue-11 dark:!bg-n-blue-8 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="loadConfiguration"
        >
          <span class="whitespace-normal">{{
            copy(busy ? 'CONFIGURING' : 'RETRY')
          }}</span>
        </Button>
        <Button
          v-else-if="selected && status === 'accepted'"
          size="lg"
          icon="i-ri-instagram-line"
          :disabled="busy || disabled"
          :is-loading="busy && operation === 'oauth'"
          class="w-full sm:w-auto !h-auto min-h-12 py-3 !bg-n-blue-11 dark:!bg-n-blue-8 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="authorize"
        >
          <span class="whitespace-normal">{{
            busy && operation === 'oauth'
              ? copy('AUTHORIZING')
              : t('INBOX_MGMT.ADD.INSTAGRAM.CONTINUE_WITH_INSTAGRAM')
          }}</span>
        </Button>
        <Button
          v-else-if="selected && status === 'absent' && !needsReconciliation"
          size="lg"
          :disabled="busy || disabled"
          :is-loading="busy && operation === 'invite'"
          class="w-full sm:w-auto !h-auto min-h-12 py-3 !bg-n-blue-11 dark:!bg-n-blue-8 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="invite"
        >
          <span class="whitespace-normal">{{
            copy(busy && operation === 'invite' ? 'INVITING' : 'INVITE')
          }}</span>
        </Button>
        <Button
          v-else-if="selected"
          size="lg"
          :disabled="busy"
          :is-loading="busy && operation === 'status'"
          class="w-full sm:w-auto !h-auto min-h-12 py-3 !bg-n-blue-11 dark:!bg-n-blue-8 hover:enabled:!brightness-100 focus-visible:!brightness-100 focus-visible:ring-2 focus-visible:ring-n-brand"
          @click="checkStatus"
        >
          <span class="whitespace-normal">{{
            copy(
              busy && operation === 'status'
                ? 'CHECKING'
                : status === 'pending'
                  ? 'VERIFY'
                  : 'CHECK_INVITE'
            )
          }}</span>
        </Button>
        <p
          v-if="selected && (status === 'pending' || needsReconciliation)"
          class="m-0 text-body-main text-n-slate-11"
        >
          {{ copy('MISSING_INVITE_HELP', parameters) }}
        </p>
        <RouterLink
          :to="{ name: 'settings_inbox_new', params: { accountId } }"
          class="inline-flex items-center min-h-11 underline text-n-slate-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ copy('BACK_CHANNELS') }}
        </RouterLink>
      </div>
    </div>
  </section>
</template>
