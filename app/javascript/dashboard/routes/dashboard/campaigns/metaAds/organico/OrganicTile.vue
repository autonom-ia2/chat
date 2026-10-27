<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { intlLocale } from '../metaAdsHelpers';

// Seus posts (#2199): um número do período, o que ele quer dizer em uma frase e a comparação com o período anterior,
// com a seta. Sem período anterior (a Meta guarda 90 dias do Instagram), a comparação some; o cartão diz por quê.
const props = defineProps({
  name: { type: String, required: true },
  icon: { type: String, required: true },
  value: { type: Number, required: true },
  previous: { type: Number, default: null },
  days: { type: Number, required: true },
  extra: { type: String, default: '' },
});

const { t, locale } = useI18n();
const KEY = 'META_ADS_ORGANIC.TILES';

const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);

const change = computed(() => {
  if (props.previous === null) return null;
  const diff = props.value - props.previous;
  if (diff === 0)
    return { text: t(`${KEY}.SAME`, { days: props.days }), tone: 'same' };
  return diff > 0
    ? {
        text: t(`${KEY}.MORE`, { count: format(diff), days: props.days }),
        tone: 'up',
      }
    : {
        text: t(`${KEY}.FEWER`, { count: format(-diff), days: props.days }),
        tone: 'down',
      };
});

const TONES = {
  up: { icon: 'i-lucide-arrow-up-right', class: 'text-n-teal-11' },
  down: { icon: 'i-lucide-arrow-down-right', class: 'text-n-ruby-11' },
  same: { icon: 'i-lucide-equal', class: 'text-n-slate-11' },
};
</script>

<template>
  <div
    :data-organic-tile="name.toLowerCase()"
    class="flex flex-col gap-1 rounded-xl bg-n-alpha-1 px-4 py-3"
  >
    <p
      class="m-0 flex items-center gap-1.5 text-sm font-medium text-n-slate-12"
    >
      <span :class="icon" class="size-4 shrink-0" aria-hidden="true" />
      {{ $t(`${KEY}.${name}.LABEL`) }}
    </p>
    <p
      class="m-0 text-2xl font-bold tabular-nums tracking-tight text-n-slate-12"
    >
      {{ format(value) }}
    </p>
    <p
      v-if="change"
      :data-organic-change="change.tone"
      class="m-0 flex items-start gap-1 text-sm"
      :class="TONES[change.tone].class"
    >
      <span
        :class="TONES[change.tone].icon"
        class="mt-0.5 size-4 shrink-0"
        aria-hidden="true"
      />
      {{ change.text }}
    </p>
    <p v-if="extra" class="m-0 text-sm text-n-slate-11">{{ extra }}</p>
    <p class="m-0 text-sm text-n-slate-11">
      {{ $t(`${KEY}.${name}.HELP`) }}
    </p>
  </div>
</template>
