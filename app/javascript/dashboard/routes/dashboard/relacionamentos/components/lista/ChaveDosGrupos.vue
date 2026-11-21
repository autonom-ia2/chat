<script setup>
import { useId } from 'vue';
import { useI18n } from 'vue-i18n';
import { VISOES } from '../../fonte/gruposDeCompra';

// #3097 — "Ver os grupos por: Conversa | Compra", acima das pílulas da aba
// Pessoas. Duas opções num grupo de rádio (setas trocam, como o padrão do
// WAI-ARIA), cada uma com 44 px de alvo. A escolhida fica branca, na cor da
// marca: é a porta de entrada dos grupos por compra e precisa ser vista.
const props = defineProps({
  modelValue: { type: String, required: true },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idDoRotulo = useId();
const OPCOES = [VISOES.CONVERSA, VISOES.COMPRA];
const ROTULOS = { [VISOES.CONVERSA]: 'CONVERSA', [VISOES.COMPRA]: 'COMPRA' };

const escolher = visao => {
  if (visao !== props.modelValue) emit('update:modelValue', visao);
};
const aoTeclar = (evento, indice) => {
  const passo = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[
    evento.key
  ];
  if (!passo) return;
  evento.preventDefault();
  const proxima = OPCOES[(indice + passo + OPCOES.length) % OPCOES.length];
  escolher(proxima);
  evento.currentTarget.parentElement
    .querySelector(`[data-visao="${proxima}"]`)
    ?.focus();
};
</script>

<template>
  <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
    <span :id="idDoRotulo" class="text-sm text-n-slate-11">
      {{ t('RELACIONAMENTOS_COMPRAS.LISTA.VISAO') }}
    </span>
    <div
      role="radiogroup"
      :aria-labelledby="idDoRotulo"
      data-relacionamentos="chave-dos-grupos"
      class="inline-flex p-0.5 rounded-lg bg-n-alpha-2"
    >
      <button
        v-for="(visao, indice) in OPCOES"
        :key="visao"
        type="button"
        role="radio"
        :data-visao="visao"
        :aria-checked="modelValue === visao"
        :tabindex="modelValue === visao ? 0 : -1"
        class="relative px-3 text-sm font-medium transition-colors rounded-md min-h-9 before:absolute before:inset-x-0 before:-inset-y-1 before:content-[''] focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        :class="
          modelValue === visao
            ? 'bg-n-solid-1 text-n-brand font-semibold shadow-sm ring-1 ring-n-weak'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="escolher(visao)"
        @keydown="aoTeclar($event, indice)"
      >
        {{ t(`RELACIONAMENTOS_COMPRAS.LISTA.${ROTULOS[visao]}`) }}
      </button>
    </div>
  </div>
</template>
