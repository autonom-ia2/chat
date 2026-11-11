<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { faixaDePreco } from '../premium';

// #2858 F7 — o preço de um card Premium, sem termo técnico: o selo "Premium", "20 grátis, depois R$ X" e quantas
// grátis ainda restam à conta. Tudo vem do servidor (`premium` de cada fonte). `completo`: no detalhe, explica também
// que a consulta sem registro conta e que o valor entra na fatura do mês.
const props = defineProps({
  premium: { type: Object, required: true },
  completo: { type: Boolean, default: false },
});

const NS = 'AGENTS.VITRINE.PREMIUM';
const { t, locale } = useI18n();

const preco = computed(() => {
  const faixa = faixaDePreco(props.premium.precos, locale.value);
  if (!faixa) return '';
  return faixa.unico || t(`${NS}.FAIXA`, { min: faixa.min, max: faixa.max });
});

const restantes = computed(() => {
  const n = Number(props.premium.restantes) || 0;
  if (n === 0) return t(`${NS}.ACABARAM`);
  return n === 1 ? t(`${NS}.RESTA_UMA`) : t(`${NS}.RESTAM`, { n });
});
</script>

<template>
  <span class="flex flex-col gap-1.5" data-vitrine-premium>
    <span class="inline-flex flex-wrap items-center gap-2">
      <span
        class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-semibold rounded-md bg-n-iris-3 text-n-iris-11"
      >
        <span class="i-lucide-gem size-3.5" aria-hidden="true" />
        {{ t(`${NS}.SELO`) }}
      </span>
      <span class="text-sm font-medium text-n-slate-12" data-vitrine-preco>
        {{ t(`${NS}.PRECO`, { gratis: premium.gratis, preco }) }}
      </span>
    </span>
    <span class="text-sm text-n-slate-11" data-vitrine-restantes>
      {{ restantes }}
    </span>
    <span v-if="completo" class="text-sm text-n-slate-11">
      {{ t(`${NS}.COMO_FUNCIONA`) }}
    </span>
  </span>
</template>
