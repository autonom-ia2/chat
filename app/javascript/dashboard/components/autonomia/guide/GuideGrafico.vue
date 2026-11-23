<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BarChart from 'shared/components/charts/BarChart.vue';

// #3158 (B8a) — o gráfico que o Guia mostra logo abaixo da resposta. Os
// números vêm da ferramenta `relatorio_de_atendimento` (os mesmos builders da
// tela Relatórios) e nunca passam pelo modelo: ele só escreve o texto.
//
// Dois modos:
//  - `ranking` (por pessoa, caixa, etiqueta, time): barras deitadas com o nome
//    inteiro. No painel de 320 px o BarChart corta o nome embaixo da barra.
//  - `serie` (por dia, semana, mês): o BarChart da tela Relatórios.
//
// Tetos da ferramenta: até 60 barras no ranking; na série, até 31 (acima de
// 31 dias ela agrupa por semana, e acima de 31 semanas por mês).
const props = defineProps({
  // 'ranking' | 'serie'.
  modo: {
    type: String,
    default: 'ranking',
    validator: valor => ['ranking', 'serie'].includes(valor),
  },
  // "Conversas resolvidas por pessoa".
  titulo: {
    type: String,
    required: true,
  },
  // O nome da medida no balão do BarChart: "Resolvidas". Só no modo série.
  medida: {
    type: String,
    default: '',
  },
  // [{ rotulo: 'Ana Souza', valor: 128 }, ...], já na ordem em que aparecem.
  barras: {
    type: Array,
    required: true,
  },
  // Datas do período no fuso da conta, 'AAAA-MM-DD'.
  de: {
    type: String,
    required: true,
  },
  ate: {
    type: String,
    required: true,
  },
});

const { t, locale } = useI18n();

// Até 14 colunas o número vai em cima de cada uma.
const LIMITE_COM_VALORES = 14;

const idioma = computed(() => locale.value.replaceAll('_', '-'));

// 'AAAA-MM-DD' é uma data de calendário, não um instante: formatada em UTC
// para o dia não escorregar com o fuso do navegador.
const diaEMes = data =>
  new Intl.DateTimeFormat(idioma.value, {
    day: '2-digit',
    month: '2-digit',
    timeZone: 'UTC',
  }).format(new Date(`${data}T00:00:00Z`));

const numero = valor => new Intl.NumberFormat(idioma.value).format(valor);

const fonte = computed(() =>
  t('AUTONOMIA_GUIDE.GRAFICO.FONTE', {
    de: diaEMes(props.de),
    ate: diaEMes(props.ate),
  })
);

const maior = computed(() =>
  Math.max(...props.barras.map(barra => barra.valor), 1)
);
const largura = valor => `${Math.round((valor / maior.value) * 100)}%`;

// Com poucas colunas o número vai em cima de cada uma; com muitas ele não
// cabe, e o rótulo de data aparece a cada N colunas (`timeseries`).
const mostraValores = computed(() => props.barras.length <= LIMITE_COM_VALORES);

const dados = computed(() => ({
  categories: props.barras.map(barra => barra.rotulo),
  series: [
    {
      id: 'valor',
      label: props.medida,
      color: 'rgb(var(--blue-9))',
      data: props.barras.map(barra => barra.valor),
    },
  ],
}));
</script>

<template>
  <figure
    class="flex flex-col gap-2 m-0 rounded-lg border border-n-weak bg-n-solid-1 p-3"
    data-grafico
  >
    <figcaption class="text-sm font-medium text-n-slate-12">
      {{ titulo }}
    </figcaption>
    <ol v-if="modo === 'ranking'" class="flex flex-col gap-2 m-0 p-0 list-none">
      <li
        v-for="(barra, indice) in barras"
        :key="indice"
        class="flex flex-col gap-1"
      >
        <span class="flex items-baseline justify-between gap-2 text-sm">
          <span class="min-w-0 break-words text-n-slate-12">
            {{ barra.rotulo }}
          </span>
          <span class="shrink-0 font-semibold tabular-nums text-n-slate-12">
            {{ numero(barra.valor) }}
          </span>
        </span>
        <span
          class="block w-full h-2 overflow-hidden rounded-full bg-n-alpha-2"
          aria-hidden="true"
        >
          <span
            class="block h-full rounded-full bg-n-brand"
            :style="{ width: largura(barra.valor) }"
          />
        </span>
      </li>
    </ol>
    <BarChart
      v-else
      :data="dados"
      :aria-label="titulo"
      :height="200"
      :max-bar-width="32"
      :show-values="mostraValores"
      timeseries
    />
    <p class="mt-1 mb-0 text-xs text-balance text-n-slate-11">{{ fonte }}</p>
  </figure>
</template>
