<script setup>
// #3098 — no topo do histórico da Automação livre: quanto as pessoas que passaram pela automação compraram em até
// 7 dias depois (a mesma régua da campanha). Primeiro o valor, que é o que o dono quer saber; depois quantas pessoas
// compraram e, por último, quantas passaram. O valor só vai para quem vê valor de venda (`valor` nulo esconde) e,
// sem ele, a contagem de quem comprou vira o número grande, com o mesmo aviso da campanha. Sem compra, o cartão fica
// neutro: o verde-água é para resultado.
//
// `resumo`: { dias, janela, passaram, compraram, valor: [{ currency, cents }] | null }
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { wonValueText } from 'dashboard/components-next/CampaignResult/resultMetrics';

const props = defineProps({
  resumo: { type: Object, required: true },
});

const NS = 'CAMPANHA_VENDAS.AUTOMACAO';
const { t, locale } = useI18n();
const idioma = computed(() => locale.value.replace('_', '-'));
const inteiro = numero => new Intl.NumberFormat(idioma.value).format(numero);
const janela = computed(() => props.resumo.janela);
const comprou = computed(() => props.resumo.compraram > 0);
const mostraValor = computed(
  () => comprou.value && Array.isArray(props.resumo.valor)
);
const valor = computed(() => wonValueText(props.resumo.valor, idioma.value));
const valorEscondido = computed(
  () => comprou.value && !Array.isArray(props.resumo.valor)
);
</script>

<template>
  <div
    class="flex flex-col gap-1 px-5 py-4 border rounded-2xl"
    :class="
      comprou ? 'border-n-teal-6 bg-n-teal-2' : 'border-n-weak bg-n-alpha-1'
    "
    data-compras-da-automacao
  >
    <p
      class="m-0 mb-1 text-xs font-semibold uppercase"
      :class="comprou ? 'text-n-teal-11' : 'text-n-slate-11'"
    >
      {{ t(`${NS}.TITULO`) }}
    </p>
    <p
      v-if="!comprou"
      class="m-0 text-base font-medium text-n-slate-12"
      data-ninguem
    >
      {{ t(`${NS}.NINGUEM`, { janela }) }}
    </p>
    <template v-else>
      <p
        v-if="mostraValor"
        class="m-0 text-2xl font-semibold tabular-nums text-n-slate-12"
        data-valor
      >
        {{ t(`${NS}.VALOR`, { valor }) }}
      </p>
      <p
        class="m-0 tabular-nums"
        :class="
          mostraValor
            ? 'text-base text-n-slate-12'
            : 'text-xl font-semibold text-n-slate-12'
        "
        data-compraram
      >
        {{
          t(
            `${NS}.COMPRARAM`,
            { n: inteiro(resumo.compraram), janela },
            resumo.compraram
          )
        }}
      </p>
    </template>
    <p class="m-0 text-sm tabular-nums text-n-slate-11" data-passaram>
      {{
        t(`${NS}.PASSARAM`, { n: inteiro(resumo.passaram) }, resumo.passaram)
      }}
    </p>
    <p
      v-if="valorEscondido"
      class="m-0 mt-1 text-xs text-n-slate-11"
      data-so-contagem
    >
      {{ t('CAMPANHA_VENDAS.RESULTADO.SO_CONTAGEM') }}
    </p>
  </div>
</template>
