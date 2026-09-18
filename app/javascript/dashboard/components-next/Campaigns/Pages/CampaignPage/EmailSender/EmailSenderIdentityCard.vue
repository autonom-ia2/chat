<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useCanManage } from 'dashboard/composables/useCanManage';

import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  identity: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['delete', 'checked']);
const canManage = useCanManage('campaign_manage');

const { t } = useI18n();
const store = useStore();
const uiFlags = useMapGetter('emailSenderIdentities/getUIFlags');

// Per-record DNS check results (filled after the user clicks "Verificar agora").
const checkResults = ref(null);

const isVerified = computed(() => props.identity.status === 'verified');
const isFailed = computed(() => props.identity.status === 'failed');

const statusLabel = computed(() => {
  switch (props.identity.status) {
    case 'pending':
      return t('CAMPAIGN.EMAIL_SENDER.STATUS.PENDING');
    case 'verifying':
      return t('CAMPAIGN.EMAIL_SENDER.STATUS.VERIFYING');
    case 'verified':
      return t('CAMPAIGN.EMAIL_SENDER.STATUS.VERIFIED');
    case 'failed':
      return t('CAMPAIGN.EMAIL_SENDER.STATUS.FAILED');
    default:
      return props.identity.status;
  }
});

const statusClass = computed(() => {
  const map = {
    pending: 'text-n-amber-11 bg-n-amber-3',
    verifying: 'text-n-blue-11 bg-n-blue-3',
    verified: 'text-n-teal-11 bg-n-teal-3',
    failed: 'text-n-ruby-11 bg-n-ruby-3',
  };
  return map[props.identity.status] || 'text-n-slate-11 bg-n-alpha-2';
});

const dnsRows = computed(() => {
  const rows = (props.identity.dkim_records || []).map(record => ({
    label: t('CAMPAIGN.EMAIL_SENDER.DNS.DKIM'),
    type: record.type,
    name: record.name,
    value: record.value,
    required: true,
  }));
  if (props.identity.spf_record) {
    rows.push({
      label: t('CAMPAIGN.EMAIL_SENDER.DNS.SPF'),
      type: 'TXT',
      name: props.identity.domain,
      value: props.identity.spf_record,
      required: false,
    });
  }
  if (props.identity.dmarc_record) {
    rows.push({
      label: t('CAMPAIGN.EMAIL_SENDER.DNS.DMARC'),
      type: 'TXT',
      name: `_dmarc.${props.identity.domain}`,
      value: props.identity.dmarc_record,
      required: false,
    });
  }
  return rows;
});

const hasDnsRecords = computed(() => dnsRows.value.length > 0);

// Overall verdict of the last per-record check: all required records resolved correctly?
const allRequiredOk = computed(() => {
  if (!checkResults.value) return false;
  return checkResults.value
    .filter(record => record.required)
    .every(record => record.status === 'ok');
});

const checkColor = status => {
  if (status === 'ok') return 'text-n-teal-11';
  if (status === 'mismatch') return 'text-n-amber-11';
  return 'text-n-ruby-11';
};

const checkMessage = status => {
  if (status === 'ok') return t('CAMPAIGN.EMAIL_SENDER.CHECK.STATUS_OK');
  if (status === 'mismatch')
    return t('CAMPAIGN.EMAIL_SENDER.CHECK.STATUS_MISMATCH');
  return t('CAMPAIGN.EMAIL_SENDER.CHECK.STATUS_MISSING');
};

const copyValue = async value => {
  await copyTextToClipboard(value);
  useAlert(t('CAMPAIGN.EMAIL_SENDER.DNS.COPIED'));
};

const runCheck = async () => {
  try {
    const data = await store.dispatch(
      'emailSenderIdentities/checkDns',
      props.identity.id
    );
    checkResults.value = data?.records || [];
    emit('checked');
  } catch (error) {
    useAlert(t('CAMPAIGN.EMAIL_SENDER.ACTIONS.ERROR'));
  }
};
</script>

<template>
  <div class="flex flex-col gap-4 p-4 border rounded-lg border-n-weak">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <p class="mb-1 font-medium truncate text-n-slate-12">
          {{ identity.domain }}
        </p>
        <span
          class="inline-flex px-2 py-1 text-xs font-medium rounded-md"
          :class="statusClass"
        >
          {{ statusLabel }}
        </span>
      </div>
      <div v-if="canManage" class="flex items-center gap-2 shrink-0">
        <Button
          v-if="!isVerified"
          :label="t('CAMPAIGN.EMAIL_SENDER.ACTIONS.CHECK')"
          icon="i-lucide-refresh-cw"
          color="blue"
          variant="outline"
          size="sm"
          :is-loading="uiFlags.isChecking"
          @click="runCheck"
        />
        <Button
          :label="t('CAMPAIGN.EMAIL_SENDER.ACTIONS.DELETE')"
          icon="i-lucide-trash-2"
          color="ruby"
          variant="ghost"
          size="sm"
          :is-loading="uiFlags.isDeleting"
          @click="emit('delete', identity.id)"
        />
      </div>
    </div>

    <!-- Humanized failure: what likely went wrong + how to fix -->
    <div
      v-if="isFailed"
      class="flex flex-col gap-1 px-3 py-2 border rounded-lg bg-n-ruby-3 border-n-ruby-4 text-n-ruby-11"
    >
      <p class="mb-0 text-sm font-medium">
        {{ t('CAMPAIGN.EMAIL_SENDER.FAILED.TITLE') }}
      </p>
      <p class="mb-0 text-xs leading-5">
        {{ t('CAMPAIGN.EMAIL_SENDER.FAILED.BODY') }}
      </p>
    </div>

    <div v-if="!isVerified && hasDnsRecords" class="flex flex-col gap-3">
      <p class="mb-0 text-sm font-medium text-n-slate-12">
        {{ t('CAMPAIGN.EMAIL_SENDER.DNS.TITLE') }}
      </p>

      <!-- Guided helper: what DNS is + where to find it + how to apply + then wait -->
      <div
        class="flex flex-col gap-2 p-3 border rounded-lg bg-n-alpha-1 border-n-weak"
      >
        <p class="mb-0 text-xs leading-5 text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.WHAT_IS') }}
        </p>
        <p class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.GUIDE_TITLE') }}
        </p>
        <ol
          class="flex flex-col gap-1 mb-0 text-xs leading-5 list-decimal ltr:pl-4 rtl:pr-4 text-n-slate-11"
        >
          <li>{{ t('CAMPAIGN.EMAIL_SENDER.DNS.GUIDE_STEP_1') }}</li>
          <li>{{ t('CAMPAIGN.EMAIL_SENDER.DNS.GUIDE_STEP_2') }}</li>
          <li>{{ t('CAMPAIGN.EMAIL_SENDER.DNS.GUIDE_STEP_3') }}</li>
          <li class="font-medium text-n-slate-12">
            {{ t('CAMPAIGN.EMAIL_SENDER.DNS.GUIDE_STEP_4') }}
          </li>
        </ol>
      </div>

      <div class="overflow-hidden border rounded-lg border-n-weak">
        <table class="w-full text-sm table-fixed">
          <thead class="bg-n-alpha-2 text-n-slate-11">
            <tr>
              <th class="w-[16%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.EMAIL_SENDER.DNS.TYPE') }}
              </th>
              <th class="w-[42%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.EMAIL_SENDER.DNS.NAME') }}
              </th>
              <th class="w-[42%] px-4 py-3 font-medium text-left">
                {{ t('CAMPAIGN.EMAIL_SENDER.DNS.VALUE') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(row, index) in dnsRows"
              :key="`${identity.id}-${index}`"
              class="align-top border-t border-n-weak"
            >
              <td class="px-4 py-3 text-n-slate-11">
                <p class="mb-0 font-medium text-n-slate-12">
                  {{ row.type }}
                </p>
                <p class="mb-0 text-xs text-n-slate-11">
                  {{ row.label }}
                </p>
                <span
                  class="inline-flex mt-1 px-1.5 py-0.5 text-[10px] font-medium rounded"
                  :class="
                    row.required
                      ? 'text-n-ruby-11 bg-n-ruby-3'
                      : 'text-n-slate-11 bg-n-alpha-2'
                  "
                >
                  {{
                    row.required
                      ? t('CAMPAIGN.EMAIL_SENDER.DNS.REQUIRED_BADGE')
                      : t('CAMPAIGN.EMAIL_SENDER.DNS.RECOMMENDED_BADGE')
                  }}
                </span>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-start gap-1">
                  <span class="break-all text-n-slate-12">{{ row.name }}</span>
                  <Button
                    icon="i-lucide-copy"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    class="shrink-0"
                    @click="copyValue(row.name)"
                  />
                </div>
              </td>
              <td class="px-4 py-3">
                <div class="flex items-start gap-1">
                  <span class="break-all text-n-slate-12">{{ row.value }}</span>
                  <Button
                    icon="i-lucide-copy"
                    color="slate"
                    variant="ghost"
                    size="xs"
                    class="shrink-0"
                    @click="copyValue(row.value)"
                  />
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- SPF explanation with a concrete before/after example -->
      <div class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak">
        <p class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.SPF_TITLE') }}
        </p>
        <p class="mb-0 text-xs leading-5 text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.SPF_HELP') }}
        </p>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.SPF_EXAMPLE_BEFORE') }}
        </p>
        <code
          class="px-2 py-1 text-xs break-all rounded bg-n-alpha-2 text-n-slate-12"
        >
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.SPF_EXAMPLE_BEFORE_VALUE') }}
        </code>
        <p class="mb-0 text-xs text-n-slate-11">
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.SPF_EXAMPLE_AFTER') }}
        </p>
        <code
          class="px-2 py-1 text-xs break-all rounded bg-n-alpha-2 text-n-slate-12"
        >
          {{ t('CAMPAIGN.EMAIL_SENDER.DNS.SPF_EXAMPLE_AFTER_VALUE') }}
        </code>
      </div>

      <!-- DMARC note: many domains already have it -->
      <p class="mb-0 text-xs leading-5 text-n-slate-11">
        {{ t('CAMPAIGN.EMAIL_SENDER.DNS.DMARC_HELP') }}
      </p>

      <p class="flex items-center gap-2 mb-0 text-xs text-n-slate-11">
        <Spinner class="w-3 h-3" />
        {{ t('CAMPAIGN.EMAIL_SENDER.DNS.AUTO_CHECKING') }}
      </p>

      <!-- Per-record live check result -->
      <div
        v-if="checkResults"
        class="flex flex-col gap-2 p-3 border rounded-lg border-n-weak"
      >
        <p class="mb-0 text-xs font-medium text-n-slate-12">
          {{ t('CAMPAIGN.EMAIL_SENDER.CHECK.TITLE') }}
        </p>
        <p
          class="mb-0 text-xs font-medium"
          :class="allRequiredOk ? 'text-n-teal-11' : 'text-n-amber-11'"
        >
          {{
            allRequiredOk
              ? t('CAMPAIGN.EMAIL_SENDER.CHECK.ALL_OK')
              : t('CAMPAIGN.EMAIL_SENDER.CHECK.HAS_ERRORS')
          }}
        </p>
        <div
          v-for="(row, index) in checkResults"
          :key="`check-${identity.id}-${index}`"
          class="flex items-start gap-2"
        >
          <Icon
            v-if="row.status === 'ok'"
            icon="i-lucide-circle-check"
            class="mt-0.5 text-base shrink-0 text-n-teal-11"
          />
          <Icon
            v-else-if="row.status === 'mismatch'"
            icon="i-lucide-triangle-alert"
            class="mt-0.5 text-base shrink-0 text-n-amber-11"
          />
          <Icon
            v-else
            icon="i-lucide-circle-x"
            class="mt-0.5 text-base shrink-0 text-n-ruby-11"
          />
          <div class="min-w-0">
            <p class="mb-0 text-xs font-medium break-all text-n-slate-12">
              {{ `${row.type} · ${row.name}` }}
            </p>
            <p class="mb-0 text-xs leading-5" :class="checkColor(row.status)">
              {{ checkMessage(row.status) }}
            </p>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
