<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { pageStatus } from '../bookingPageStatus';

// O selo de situação de uma página de agendamento (#1371): No ar, Pausada ou
// Rascunho. Mora aqui para o cartão da lista e a gaveta "Marcar reuniões" do
// agente de IA mostrarem o mesmo selo. Recebe a situação pronta (`status`) ou a
// página como a API devolve (`page`), e então a deduz como o cartão sempre fez.
const props = defineProps({
  // 'LIVE' | 'PAUSED' | 'DRAFT'. Vazio: deduz da `page`.
  status: { type: String, default: '' },
  page: { type: Object, default: null },
});

const { t } = useI18n();

const STATUSES = ['LIVE', 'PAUSED', 'DRAFT'];
const current = computed(() =>
  STATUSES.includes(props.status) ? props.status : pageStatus(props.page)
);

const label = computed(() => {
  if (current.value === 'LIVE') return t('BOOKING.CARD.STATUS.LIVE');
  if (current.value === 'DRAFT') return t('BOOKING.CARD.STATUS.DRAFT');
  return t('BOOKING.CARD.STATUS.PAUSED');
});
const STATUS_TONE = {
  LIVE: { badge: 'bg-n-teal-3 text-n-teal-11', dot: 'bg-n-teal-9' },
  PAUSED: { badge: 'bg-n-slate-3 text-n-slate-11', dot: 'bg-n-slate-9' },
  DRAFT: { badge: 'bg-n-amber-3 text-n-amber-11', dot: 'bg-n-amber-9' },
};
</script>

<template>
  <span
    data-status
    class="inline-flex items-center gap-2 px-3 py-1 text-sm font-semibold rounded-full"
    :data-status-key="current"
    :class="STATUS_TONE[current].badge"
  >
    <span
      class="size-2 rounded-full"
      :class="STATUS_TONE[current].dot"
      aria-hidden="true"
    />
    {{ label }}
  </span>
</template>
