<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import CrmMetaAdsConnectionAPI from 'dashboard/api/crmMetaAdsConnection';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

// Paste-and-test of the Meta ads read token (docs/crm/origens-nomes-meta.md §2).
// The token lives only in this field until it is sent; it is never logged.
const emit = defineEmits(['connected']);

const { t } = useI18n();

const steps = computed(() => [
  t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.STEP_1'),
  t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.STEP_2'),
  t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.STEP_3'),
  t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.STEP_4'),
]);

const dialog = ref(null);
const token = ref('');
const errorCode = ref('');
const isSaving = ref(false);

// One text per code the controller answers. Only meta_unavailable and network
// failures are worth retrying, so only they fall to the generic "try again".
const errorMessage = computed(() => {
  switch (errorCode.value) {
    case '':
      return '';
    case 'missing_ads_read':
      return t(
        'CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_MISSING_ADS_READ'
      );
    case 'invalid_token':
    case 'access_token_too_long':
      return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_INVALID_TOKEN');
    case 'no_ad_account':
      return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_NO_AD_ACCOUNT');
    case 'access_token_required':
      return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_TOKEN_REQUIRED');
    case 'encryption_not_configured':
      return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_ENCRYPTION');
    case 'forbidden':
      return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_FORBIDDEN');
    default:
      return t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.ERROR_GENERIC');
  }
});

const reset = () => {
  token.value = '';
  errorCode.value = '';
};

const open = () => {
  reset();
  dialog.value.open();
};

const save = async () => {
  const accessToken = token.value.trim();
  if (!accessToken || isSaving.value) return;
  isSaving.value = true;
  errorCode.value = '';
  try {
    const { data } = await CrmMetaAdsConnectionAPI.update(accessToken);
    reset();
    dialog.value.close();
    emit('connected', data);
  } catch (error) {
    // Only the error code is read; the request (and its token) is never kept.
    errorCode.value = error?.response?.data?.error || 'unknown';
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.TITLE')"
    :description="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.DESCRIPTION')"
    :confirm-button-label="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.SAVE')"
    :disable-confirm-button="!token.trim()"
    :is-loading="isSaving"
    @confirm="save"
    @close="reset"
  >
    <div class="grid gap-5">
      <div class="rounded-lg bg-n-alpha-1 p-4">
        <p class="m-0 text-sm font-medium text-n-slate-12">
          {{ t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.STEPS_TITLE') }}
        </p>
        <ol class="m-0 mt-2 grid list-none gap-1.5 p-0 text-sm text-n-slate-11">
          <li
            v-for="(step, index) in steps"
            :key="index"
            class="flex items-start gap-2"
          >
            <span
              class="mt-0.5 flex size-5 shrink-0 items-center justify-center rounded-full bg-n-alpha-2 text-[11px] font-semibold tabular-nums text-n-slate-12"
              aria-hidden="true"
            >
              {{ index + 1 }}
            </span>
            <span>{{ step }}</span>
          </li>
        </ol>
      </div>

      <div class="grid gap-1.5">
        <Input
          v-model="token"
          type="password"
          autocomplete="off"
          spellcheck="false"
          :label="t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.TOKEN_LABEL')"
          :placeholder="
            t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.TOKEN_PLACEHOLDER')
          "
          :message-type="errorMessage ? 'error' : 'info'"
          :disabled="isSaving"
          custom-input-class="!h-11 font-mono"
        />
        <p
          v-if="errorMessage"
          role="alert"
          class="m-0 text-sm leading-5 text-n-ruby-11"
          data-testid="meta-ads-error"
        >
          {{ errorMessage }}
        </p>
        <p v-else class="m-0 text-xs leading-5 text-n-slate-11">
          {{ t('CRM_KANBAN.TRACKED_LINKS.META_ADS.DIALOG.TOKEN_PRIVACY') }}
        </p>
      </div>
    </div>
  </Dialog>
</template>
