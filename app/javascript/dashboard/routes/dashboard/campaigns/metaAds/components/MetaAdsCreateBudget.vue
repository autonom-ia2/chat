<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { money, todayOfAccount } from '../dinheiroDoAnuncio';
import CampoDeData from './CampoDeData.vue';
import CampoDeValor from './CampoDeValor.vue';
import MetaAdsEndDate from './MetaAdsEndDate.vue';

// Anúncios da Meta (#2198), criar: quanto por dia e até quando. Começa pronto (R$ 20,00 sugeridos, começando hoje,
// sem data para terminar); embaixo, o que a Meta pode gastar num dia e na semana e o total, que o pai calcula.
const props = defineProps({
  limits: { type: Object, required: true },
  amountError: { type: String, default: '' },
  totalLine: { type: String, default: '' },
  dayLimitsLine: { type: String, default: '' },
  suggestion: { type: Number, required: true },
});

const draft = defineModel({ type: Object, required: true });

const { t, locale } = useI18n();
const KEY = 'CRM_KANBAN.META_ADS_HUB.CRIAR.BUDGET';

const fmt = value => money(value, props.limits.currency, locale.value);

const set = (field, value) => {
  draft.value = { ...draft.value, [field]: value };
};

// Começo depois do fim: o fim volta para "sem data".
const setStart = value => {
  const end = draft.value.end_date;
  draft.value = {
    ...draft.value,
    start_date: value,
    end_date: end && end < value ? '' : end,
  };
};

const hint = computed(
  () =>
    props.amountError ||
    t(`${KEY}.SUGGESTION`, {
      value: fmt(props.suggestion),
      min: fmt(props.limits.min_daily),
      max: fmt(props.limits.max_daily),
    })
);
</script>

<template>
  <div class="flex min-w-0 max-w-xl flex-col gap-5">
    <CampoDeValor
      :model-value="draft.daily_amount"
      data-create-amount
      :currency="limits.currency"
      :error="Boolean(amountError)"
      :label="$t(`${KEY}.AMOUNT`)"
      :message="hint"
      @update:model-value="set('daily_amount', $event)"
    />
    <p
      v-if="dayLimitsLine && !amountError"
      data-create-day-limits
      class="m-0 text-sm text-n-slate-11"
    >
      {{ dayLimitsLine }}
    </p>
    <CampoDeData
      :model-value="draft.start_date"
      data-create-start
      :label="$t(`${KEY}.START`)"
      :min="todayOfAccount(limits.today)"
      @update:model-value="setStart"
    />
    <MetaAdsEndDate
      :model-value="draft.end_date"
      :from="draft.start_date"
      @update:model-value="set('end_date', $event)"
    />
    <p
      v-if="totalLine && !amountError"
      data-create-total
      class="m-0 rounded-xl bg-n-alpha-1 p-4 text-sm text-n-slate-12"
    >
      {{ totalLine }}
    </p>
  </div>
</template>
