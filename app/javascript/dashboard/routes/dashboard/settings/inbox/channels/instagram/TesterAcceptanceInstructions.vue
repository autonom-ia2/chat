<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { INSTAGRAM_ACCEPTANCE_URL } from 'dashboard/composables/useInstagramTester';

const props = defineProps({
  username: { type: String, required: true },
  appName: { type: String, required: true },
});
const { t } = useI18n();
const parameters = computed(() => ({
  username: props.username,
  appName: props.appName,
}));
</script>

<template>
  <ol class="list-decimal ps-5 m-0 space-y-3 text-body-main break-words">
    <li>
      {{ t('INBOX_MGMT.ADD.INSTAGRAM.TESTER.ACCEPT_COMPUTER', parameters) }}
    </li>
    <li>{{ t('INBOX_MGMT.ADD.INSTAGRAM.TESTER.ACCEPT_PATH') }}</li>
    <li>{{ t('INBOX_MGMT.ADD.INSTAGRAM.TESTER.ACCEPT_APP', parameters) }}</li>
    <li>{{ t('INBOX_MGMT.ADD.INSTAGRAM.TESTER.ACCEPT_RETURN') }}</li>
  </ol>
  <a
    :href="INSTAGRAM_ACCEPTANCE_URL"
    target="_blank"
    rel="noopener noreferrer"
    class="inline-flex items-center min-h-11 gap-2 underline text-n-blue-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
  >
    {{ t('INBOX_MGMT.ADD.INSTAGRAM.TESTER.OPEN_APPS') }}
    <Icon
      icon="i-lucide-external-link"
      class="size-4 shrink-0"
      aria-hidden="true"
    />
  </a>
  <p class="m-0 text-label-small text-n-slate-11">
    {{ t('INBOX_MGMT.ADD.INSTAGRAM.TESTER.LINK_HELP', parameters) }}
  </p>
</template>
