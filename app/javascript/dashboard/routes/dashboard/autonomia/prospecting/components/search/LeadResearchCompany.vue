<script setup>
// Bloco Empresa do painel lateral (#679), como o do Orth
// (DecisionResearchPanel.tsx): razão social, nome fantasia só quando difere,
// CNPJ com botão de copiar, situação cadastral e UF, e alerta quando a
// situação não é ATIVA. Sem CNPJ nem razão social, o bloco não aparece.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import {
  cnpjDigits,
  formatCnpj,
  isRegistryInactive,
  tradeNameToShow,
} from '../../utils/leadResearch';

const props = defineProps({
  company: { type: Object, default: null },
});

const { t } = useI18n();

const legalName = computed(() => props.company?.legal_name?.trim() || null);
const cnpj = computed(() => props.company?.cnpj?.trim() || null);
const formattedCnpj = computed(() => formatCnpj(cnpj.value));
const tradeName = computed(() => tradeNameToShow(props.company));
const status = computed(
  () => props.company?.registration_status?.trim() || null
);
const hasData = computed(() => Boolean(cnpj.value || legalName.value));
const isInactive = computed(
  () => hasData.value && isRegistryInactive(status.value)
);
const statusText = computed(() => {
  const state = props.company?.registration_state?.trim();
  return state
    ? `${status.value} · ${t('PROSPECTING.RESEARCH.PANEL.REGISTRATION_STATE', { state })}`
    : status.value;
});

const copyCnpj = async () => {
  try {
    await copyTextToClipboard(cnpjDigits(cnpj.value));
    useAlert(t('PROSPECTING.RESEARCH.PANEL.CNPJ_COPIED'));
  } catch {
    useAlert(t('PROSPECTING.RESEARCH.PANEL.CNPJ_COPY_FAILED'));
  }
};
</script>

<template>
  <section
    v-if="hasData"
    data-test="research-company"
    class="rounded-md border border-n-weak bg-n-solid-1 p-3"
  >
    <h4 class="text-xs font-semibold uppercase tracking-wide text-n-slate-10">
      {{ t('PROSPECTING.RESEARCH.PANEL.COMPANY_TITLE') }}
    </h4>
    <dl
      class="mt-2 grid grid-cols-[minmax(0,7rem)_minmax(0,1fr)] gap-x-3 gap-y-2"
    >
      <template v-if="legalName">
        <dt class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.RESEARCH.PANEL.LEGAL_NAME') }}
        </dt>
        <dd class="min-w-0 break-words text-sm text-n-slate-12">
          {{ legalName }}
        </dd>
      </template>
      <template v-if="tradeName">
        <dt class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.RESEARCH.PANEL.TRADE_NAME') }}
        </dt>
        <dd class="min-w-0 break-words text-sm text-n-slate-12">
          {{ tradeName }}
        </dd>
      </template>
      <template v-if="cnpj">
        <dt class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.RESEARCH.PANEL.CNPJ') }}
        </dt>
        <dd class="min-w-0 text-sm text-n-slate-12">
          <button
            type="button"
            class="inline-flex min-h-11 items-center rounded-sm text-left hover:underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand"
            :aria-label="
              t('PROSPECTING.RESEARCH.PANEL.COPY_CNPJ', {
                cnpj: formattedCnpj,
              })
            "
            @click="copyCnpj"
          >
            {{
              `${formattedCnpj} · ${t('PROSPECTING.RESEARCH.PANEL.COPY_SUFFIX')}`
            }}
          </button>
        </dd>
      </template>
      <template v-if="status">
        <dt class="text-xs text-n-slate-10">
          {{ t('PROSPECTING.RESEARCH.PANEL.REGISTRATION_STATUS') }}
        </dt>
        <dd
          data-test="research-registration"
          class="min-w-0 text-sm"
          :class="
            isInactive ? 'font-medium text-n-amber-11' : 'text-n-slate-12'
          "
        >
          {{ statusText }}
        </dd>
      </template>
    </dl>
    <p
      v-if="isInactive"
      role="alert"
      class="mt-3 rounded-md border border-n-amber-5 bg-n-amber-2 p-3 text-sm font-medium text-n-amber-11"
    >
      {{ t('PROSPECTING.RESEARCH.PANEL.INACTIVE_ALERT', { status }) }}
    </p>
  </section>
</template>
