<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

// Seus posts (#2199): a frase que responde "vale pagar?" (Página: vezes que apareceu sem pagar × por anúncio) ou
// "estou chegando a gente nova?" (Instagram: quem viu e ainda não segue × quem já segue), com a barra das duas partes.
// A barra é SVG: a largura vai no atributo do retângulo, sem estilo inline.
const props = defineProps({
  // Chave do bloco no i18n (ADS_SHARE ou NEW_PEOPLE): TEXT, FIRST e SECOND.
  textKey: { type: String, required: true },
  part: { type: Number, required: true },
  total: { type: Number, required: true },
  // Cor da 2ª parte: azul é "de anúncios" (Página); no Instagram ("já segue") é cinza, para a mesma cor não ter dois
  // sentidos lado a lado.
  secondTone: { type: String, default: 'blue' },
});

const { t } = useI18n();

// Frase e legendas de cada barra com a chave escrita inteira: a checagem de i18n confere cada uma.
const barTexts = (first, second) => ({
  ADS_SHARE: {
    text: t('META_ADS_ORGANIC.ADS_SHARE.TEXT', { first, second }),
    first: t('META_ADS_ORGANIC.ADS_SHARE.FIRST'),
    second: t('META_ADS_ORGANIC.ADS_SHARE.SECOND'),
  },
  NEW_PEOPLE: {
    text: t('META_ADS_ORGANIC.NEW_PEOPLE.TEXT', { first, second }),
    first: t('META_ADS_ORGANIC.NEW_PEOPLE.FIRST'),
    second: t('META_ADS_ORGANIC.NEW_PEOPLE.SECOND'),
  },
});

const SECOND = {
  blue: { fill: 'fill-n-blue-9', dot: 'bg-n-blue-9' },
  slate: { fill: 'fill-n-slate-6', dot: 'bg-n-slate-6' },
};

const first = computed(() =>
  props.total ? Math.round((props.part / props.total) * 100) : 0
);
const second = computed(() => 100 - first.value);
const texts = computed(
  () => barTexts(first.value, second.value)[props.textKey]
);
</script>

<template>
  <div
    :data-organic-share="textKey.toLowerCase()"
    class="flex flex-col gap-2 rounded-xl bg-n-alpha-1 p-4"
  >
    <p
      class="m-0 text-pretty text-base font-semibold leading-snug text-n-slate-12"
    >
      {{ texts.text }}
    </p>
    <svg
      class="h-3 w-full overflow-hidden rounded-full"
      role="img"
      :aria-label="texts.text"
    >
      <rect
        x="0"
        y="0"
        height="100%"
        :width="`${first}%`"
        class="fill-n-teal-9"
      />
      <rect
        :x="`${first}%`"
        y="0"
        height="100%"
        :width="`${second}%`"
        :class="SECOND[secondTone].fill"
      />
    </svg>
    <p class="m-0 flex flex-wrap gap-x-4 gap-y-1 text-sm text-n-slate-11">
      <span class="inline-flex items-center gap-1.5">
        <span class="size-2.5 rounded-full bg-n-teal-9" aria-hidden="true" />
        {{ texts.first }}
      </span>
      <span class="inline-flex items-center gap-1.5">
        <span
          class="size-2.5 rounded-full"
          :class="SECOND[secondTone].dot"
          aria-hidden="true"
        />
        {{ texts.second }}
      </span>
    </p>
  </div>
</template>
