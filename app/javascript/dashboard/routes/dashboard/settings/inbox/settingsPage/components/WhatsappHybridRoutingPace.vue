<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import SentenceChoice from 'dashboard/components-next/sentence-choice/SentenceChoice.vue';
import {
  PACE_OPTIONS,
  PACE_RECOMMENDED,
  PACE_MIN,
  PACE_MAX,
  PACE_OTHER,
  paceChoiceFor,
  validPace,
} from '../whatsappHybridState';

// chat#1487 — o ritmo escolhido dentro da frase: 10, 20 ou 30 por minuto, ou "Outro…" com o campo numérico (mesmos
// limites do servidor). Valor salvo fora das três abre já em "Outro", com ele no campo.
const props = defineProps({
  campaignLimit: { type: Number, required: true },
});
const rate = defineModel({ type: Number, required: true });

const { t } = useI18n();
const P = 'INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.PACE';
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const tp = (key, params) => t(`${P}.${key}`, params);

const choice = ref(paceChoiceFor(rate.value));
const other = ref(choice.value === PACE_OTHER ? String(rate.value) : '');
const otherNumber = computed(() => Number(other.value));
const invalid = computed(
  () => choice.value === PACE_OTHER && !validPace(otherNumber.value)
);

const options = computed(() => [
  ...PACE_OPTIONS.map(value => ({ value, label: String(value) })),
  { value: PACE_OTHER, label: tp('OTHER') },
]);

watch(choice, value => {
  if (value !== PACE_OTHER) rate.value = value;
  else if (validPace(otherNumber.value)) rate.value = otherNumber.value;
});
watch(otherNumber, value => {
  if (choice.value === PACE_OTHER && validPace(value)) rate.value = value;
});

defineExpose({ invalid });
// O limite das campanhas nunca passa do ritmo geral (WhatsappHybrid::RateLimit).
const campaignCap = computed(() => Math.min(props.campaignLimit, rate.value));
</script>

<template>
  <div class="flex flex-col gap-3">
    <p class="mb-0 text-base leading-relaxed text-n-slate-12">
      {{ tp('BEFORE') }}
      <SentenceChoice
        v-model="choice"
        :options="options"
        :label="tp('CHOICE_LABEL')"
      />
      {{ tp('AFTER') }}
    </p>
    <p class="mb-0 text-sm text-n-slate-11">
      {{ tp('RECOMMENDED', { n: PACE_RECOMMENDED }) }}
    </p>
    <div v-if="choice === PACE_OTHER" class="flex flex-col gap-1">
      <label for="hybrid-pace-other" class="text-sm text-n-slate-12">
        {{ tp('OTHER_LABEL', { min: PACE_MIN, max: PACE_MAX }) }}
      </label>
      <input
        id="hybrid-pace-other"
        v-model="other"
        data-pace-other
        type="number"
        inputmode="numeric"
        :min="PACE_MIN"
        :max="PACE_MAX"
        :aria-invalid="invalid || undefined"
        aria-describedby="hybrid-pace-other-error"
        class="w-28 px-3 mb-0 text-base border rounded-xl min-h-11 bg-n-alpha-black2 text-n-slate-12"
        :class="invalid ? 'border-n-ruby-8' : 'border-n-weak'"
      />
      <p
        v-if="invalid"
        id="hybrid-pace-other-error"
        role="alert"
        class="mb-0 text-sm text-n-ruby-11"
      >
        {{ tp('INVALID', { min: PACE_MIN, max: PACE_MAX }) }}
      </p>
    </div>
    <p
      data-campaign-cap
      class="flex items-start gap-2 px-4 py-3 mb-0 text-sm rounded-xl bg-n-alpha-1 text-n-slate-12"
    >
      <span
        class="i-lucide-shield-check size-4 mt-0.5 shrink-0 text-n-teal-11"
        aria-hidden="true"
      />
      {{ tp('CAMPAIGNS', { limit: campaignCap }) }}
    </p>
  </div>
</template>
