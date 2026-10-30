<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { intlLocale } from '../metaAdsHelpers';

// Seus posts (#2199): um número do período, o que ele quer dizer em uma frase e a comparação com o período anterior,
// com a seta. Sem período anterior (a Meta guarda 90 dias do Instagram), a comparação some; o cartão diz por quê.
const props = defineProps({
  name: { type: String, required: true },
  icon: { type: String, required: true },
  // null: a Meta não mandou o número (aparece "—", nunca 0).
  value: { type: Number, default: null },
  previous: { type: Number, default: null },
  days: { type: Number, required: true },
  extra: { type: String, default: '' },
  // O número é teto, não conta exata (quem viu no Instagram: a Meta não deduplica entre tipos de post).
  upTo: { type: Boolean, default: false },
});

const { t, locale } = useI18n();
// Nome e explicação de cada quadro com a chave escrita inteira: a checagem de i18n confere cada uma.
const tileTexts = () => ({
  REACH: {
    label: t('META_ADS_ORGANIC.TILES.REACH.LABEL'),
    help: props.upTo
      ? t('META_ADS_ORGANIC.TILES.REACH.HELP_UP_TO')
      : t('META_ADS_ORGANIC.TILES.REACH.HELP'),
  },
  VIEWS: {
    label: t('META_ADS_ORGANIC.TILES.VIEWS.LABEL'),
    help: t('META_ADS_ORGANIC.TILES.VIEWS.HELP'),
  },
  INTERACTIONS: {
    label: t('META_ADS_ORGANIC.TILES.INTERACTIONS.LABEL'),
    help: t('META_ADS_ORGANIC.TILES.INTERACTIONS.HELP'),
  },
  FOLLOWERS: {
    label: t('META_ADS_ORGANIC.TILES.FOLLOWERS.LABEL'),
    help: t('META_ADS_ORGANIC.TILES.FOLLOWERS.HELP'),
  },
});
const texts = computed(() => tileTexts()[props.name]);

const format = value =>
  new Intl.NumberFormat(intlLocale(locale.value)).format(value);

const shown = computed(() => {
  if (props.value === null) return '—';
  return props.upTo && props.value
    ? t('META_ADS_ORGANIC.TILES.UP_TO', { count: format(props.value) })
    : format(props.value);
});

// Teto contra teto não dá diferença exata: o quadro "até N" fica sem a linha "X a mais".
const change = computed(() => {
  if (props.previous === null || props.value === null || props.upTo)
    return null;
  const diff = props.value - props.previous;
  if (diff === 0)
    return {
      text: t('META_ADS_ORGANIC.TILES.SAME', { days: props.days }),
      tone: 'same',
    };
  return diff > 0
    ? {
        text: t('META_ADS_ORGANIC.TILES.MORE', {
          count: format(diff),
          days: props.days,
        }),
        tone: 'up',
      }
    : {
        text: t('META_ADS_ORGANIC.TILES.FEWER', {
          count: format(-diff),
          days: props.days,
        }),
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
      {{ texts.label }}
    </p>
    <p
      class="m-0 text-2xl font-bold tabular-nums tracking-tight text-n-slate-12"
    >
      {{ shown }}
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
      {{ texts.help }}
    </p>
  </div>
</template>
