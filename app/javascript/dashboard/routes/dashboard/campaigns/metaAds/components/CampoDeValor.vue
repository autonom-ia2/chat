<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { intlLocale } from '../metaAdsHelpers';

// Anúncios da Meta (#2198): campo de dinheiro com o símbolo da moeda dentro ("R$ 20,00"), para não haver dúvida do
// que digitar. Com a cara do Input do painel. Quem digita "R$ 45" também acerta: parseAmount ignora o símbolo.
const props = defineProps({
  label: { type: String, required: true },
  currency: { type: String, default: 'BRL' },
  message: { type: String, default: '' },
  error: { type: Boolean, default: false },
});

defineOptions({ inheritAttrs: false });

const model = defineModel({ type: String, default: '' });

const { locale } = useI18n();
const uid = Math.random().toString(36).slice(2, 8);

// Sem moeda confirmada pelo servidor, sem símbolo: nunca presume real.
const symbol = computed(() =>
  props.currency
    ? new Intl.NumberFormat(intlLocale(locale.value), {
        style: 'currency',
        currency: props.currency,
      })
        .formatToParts(0)
        .find(part => part.type === 'currency')?.value || ''
    : ''
);
</script>

<template>
  <div class="flex min-w-0 flex-col gap-1">
    <label :for="`valor-${uid}`" class="mb-0.5 text-heading-3 text-n-slate-12">
      {{ label }}
    </label>
    <div
      class="flex h-11 items-center gap-2 rounded-lg bg-n-alpha-black2 px-3 outline outline-1"
      :class="
        error
          ? 'outline-n-ruby-8 focus-within:outline-n-ruby-9'
          : 'outline-n-weak hover:outline-n-slate-6 focus-within:outline-n-brand'
      "
    >
      <span class="text-sm font-medium text-n-slate-11" aria-hidden="true">
        {{ symbol }}
      </span>
      <input
        :id="`valor-${uid}`"
        v-bind="$attrs"
        v-model="model"
        inputmode="decimal"
        autocomplete="off"
        :aria-invalid="error"
        :aria-describedby="message ? `valor-${uid}-msg` : undefined"
        class="!m-0 h-full min-w-0 flex-1 !border-0 !bg-transparent !p-0 text-sm tabular-nums text-n-slate-12 !shadow-none !outline-none"
      />
    </div>
    <p
      v-if="message"
      :id="`valor-${uid}-msg`"
      class="m-0 text-xs"
      :class="error ? 'text-n-ruby-11' : 'text-n-slate-11'"
    >
      {{ message }}
    </p>
  </div>
</template>
