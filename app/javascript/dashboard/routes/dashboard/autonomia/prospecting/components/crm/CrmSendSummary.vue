<script setup>
// Resumo do envio ao CRM (#680): criados, já existentes e falhas com o motivo
// de cada lead. O título segue o que aconteceu de fato; com tudo falhando,
// nada aqui fala em card criado.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { sendOutcome } from '../../utils/crmSend';

const props = defineProps({
  summary: { type: Object, required: true },
  leads: { type: Array, required: true },
});

const OUTCOME_CLASSES = {
  success: 'border-n-teal-5 bg-n-teal-2 text-n-teal-11',
  partial: 'border-n-amber-5 bg-n-amber-2 text-n-amber-11',
  failed: 'border-n-ruby-5 bg-n-ruby-2 text-n-ruby-11',
};

const { t } = useI18n();

const outcome = computed(() => sendOutcome(props.summary));
const title = computed(
  () =>
    ({
      success: t('PROSPECTING.CRM_SEND.RESULT.SUCCESS_TITLE'),
      partial: t('PROSPECTING.CRM_SEND.RESULT.PARTIAL_TITLE'),
      failed: t('PROSPECTING.CRM_SEND.RESULT.FAILED_TITLE'),
    })[outcome.value]
);
// Motivo sem mensagem do servidor: o texto da tela para o código.
const reasonText = reasonCode => {
  if (reasonCode === 'not_found') {
    return t('PROSPECTING.CRM_SEND.FAILURE_REASONS.NOT_FOUND');
  }
  if (reasonCode === 'request_failed') {
    return t('PROSPECTING.CRM_SEND.FAILURE_REASONS.REQUEST_FAILED');
  }
  return t('PROSPECTING.CRM_SEND.FAILURE_REASONS.DEFAULT');
};
const leadNames = computed(
  () => new Map(props.leads.map(lead => [Number(lead.id), lead.name]))
);
const failures = computed(() =>
  props.summary.failed.map(item => ({
    leadId: item.lead_id,
    name:
      leadNames.value.get(Number(item.lead_id)) ||
      t('PROSPECTING.CRM_SEND.RESULT.UNKNOWN_LEAD', { id: item.lead_id }),
    reason: item.message || reasonText(item.reason_code),
  }))
);
const counts = computed(() => {
  const { created, existing, failed } = props.summary;
  return [
    created.length &&
      t('PROSPECTING.CRM_SEND.RESULT.CREATED', { count: created.length }),
    existing.length &&
      t('PROSPECTING.CRM_SEND.RESULT.EXISTING', { count: existing.length }),
    failed.length &&
      t('PROSPECTING.CRM_SEND.RESULT.FAILED', { count: failed.length }),
  ].filter(Boolean);
});
</script>

<template>
  <section data-test="crm-send-summary" class="grid gap-3" aria-live="polite">
    <div
      class="rounded-md border p-3 text-sm font-semibold"
      :class="OUTCOME_CLASSES[outcome]"
    >
      {{ title }}
    </div>
    <ul class="grid gap-1 text-sm text-n-slate-12">
      <li v-for="line in counts" :key="line">{{ line }}</li>
    </ul>
    <div v-if="failures.length" class="grid gap-2">
      <h3 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
        {{ t('PROSPECTING.CRM_SEND.RESULT.FAILED_LIST') }}
      </h3>
      <ul
        class="grid max-h-48 gap-1.5 overflow-y-auto rounded-md border border-n-weak bg-n-solid-2 p-3"
      >
        <li
          v-for="failure in failures"
          :key="failure.leadId"
          data-test="crm-send-failure"
          class="break-words text-sm text-n-slate-12"
        >
          {{ `${failure.name} · ${failure.reason}` }}
        </li>
      </ul>
    </div>
  </section>
</template>
