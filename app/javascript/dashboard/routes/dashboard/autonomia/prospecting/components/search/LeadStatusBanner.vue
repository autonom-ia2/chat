<script setup>
// Faixa do lead já no CRM ou descartado (#732), no topo do card e do painel,
// como a faixa de "Já é cliente" do Orth (ResultsTable.tsx). No CRM: funil,
// estágio e responsável do card que o lead tem. Descartado: o motivo.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  crmPresenceDetail,
  isLeadDiscarded,
  isLeadInCrm,
} from '../../utils/leadCrmPresence';

const props = defineProps({
  lead: { type: Object, required: true },
  showReason: { type: Boolean, default: true },
});

const { t } = useI18n();

const discarded = computed(() => isLeadDiscarded(props.lead));
const inCrm = computed(() => isLeadInCrm(props.lead));
const detail = computed(() => {
  if (discarded.value) return props.showReason ? props.lead.discard_reason : '';
  return crmPresenceDetail(props.lead, t('PROSPECTING.LEAD_STATUS.NO_OWNER'));
});
</script>

<template>
  <div
    v-if="discarded || inCrm"
    data-test="lead-status"
    class="flex min-w-0 flex-wrap items-center gap-1.5 px-4 py-1.5 text-[11px]"
    :class="
      discarded
        ? 'bg-n-slate-3 text-n-slate-11'
        : 'bg-n-teal-2 text-n-teal-11 ring-1 ring-n-teal-5'
    "
  >
    <span
      class="size-3.5 shrink-0"
      :class="discarded ? 'i-lucide-ban' : 'i-lucide-kanban-square'"
      aria-hidden="true"
    />
    <span class="font-semibold">
      {{
        discarded
          ? t('PROSPECTING.LEAD_STATUS.DISCARDED')
          : t('PROSPECTING.LEAD_STATUS.IN_CRM')
      }}
    </span>
    <span v-if="detail" class="min-w-0 break-words">{{ detail }}</span>
  </div>
</template>
