<script setup>
import { computed } from 'vue';
import { useNumerosFormato } from '../useNumerosFormato';

// Números › Origens (#2001, F6) — pergunta 3: "Quanto você pagou por cada venda?". Só existe com gasto conectado e em
// "Todos os funis" (quem monta a tela não a renderiza sem `gasto`): nada de zero, traço ou convite. Frase de
// dono, sem sigla. Os três números no mesmo formato (centavos), cada um com o rótulo embaixo. O link para os
// anúncios fica uma vez só, no fim da pergunta 4.
const props = defineProps({
  gasto: { type: Object, required: true },
  mesNome: { type: String, required: true },
  moeda: { type: String, default: 'BRL' },
});

const O = 'CRM_NUMEROS_ORIGENS';
const { t, dinheiro, locale } = useNumerosFormato(props.moeda);
const centavos = new Intl.NumberFormat(locale(), {
  style: 'currency',
  currency: props.moeda,
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

const numeros = computed(() =>
  [
    {
      chave: 'total',
      grande: centavos.format(props.gasto.total),
      rotulo: t(`${O}.GASTO.TOTAL`, { mes: props.mesNome }),
    },
    props.gasto.porCliente !== null && {
      chave: 'por-cliente',
      grande: centavos.format(props.gasto.porCliente),
      rotulo: t(`${O}.GASTO.POR_CLIENTE`),
    },
    props.gasto.porVenda !== null && {
      chave: 'por-venda',
      grande: centavos.format(props.gasto.porVenda),
      rotulo: t(`${O}.GASTO.POR_VENDA`),
    },
  ].filter(Boolean)
);
const retorno = computed(() =>
  props.gasto.retorno === null
    ? ''
    : t(`${O}.GASTO.RETORNO`, {
        um: dinheiro(1),
        valor: dinheiro(props.gasto.retorno),
      })
);
</script>

<template>
  <section
    data-origens-bloco="gasto"
    aria-labelledby="origens-gasto"
    class="flex flex-col gap-3"
  >
    <h2 id="origens-gasto" class="mb-0 text-base font-semibold text-n-slate-12">
      {{ t(`${O}.GASTO.TITULO`) }}
    </h2>
    <div
      class="flex flex-col gap-3 rounded-xl bg-n-solid-1 p-4 ring-1 ring-inset ring-n-weak"
    >
      <p
        v-if="retorno"
        data-gasto="retorno"
        class="mb-0 rounded-lg bg-n-teal-3 px-3 py-2 text-base font-semibold text-n-teal-12"
      >
        {{ retorno }}
      </p>
      <ul class="m-0 grid list-none grid-cols-1 gap-3 p-0 sm:grid-cols-3">
        <li
          v-for="numero in numeros"
          :key="numero.chave"
          :data-gasto="numero.chave"
          class="flex flex-col gap-0.5"
        >
          <strong
            class="text-xl font-semibold tabular-nums text-n-slate-12 sm:text-2xl"
          >
            {{ numero.grande }}
          </strong>
          <span class="text-sm text-n-slate-11">{{ numero.rotulo }}</span>
        </li>
      </ul>
    </div>
  </section>
</template>
