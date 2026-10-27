<script setup>
import { computed, ref } from 'vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import TabelaDoPainel from './TabelaDoPainel.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { pct as pctDe } from '../../../utils/desempenhoContrato';
import { ordenar, totalDoPeriodo } from '../../../utils/desempenhoDetalhe';

// #2226 v2 — uma linha por dia ou semana do gráfico de evolução, com o total do período no fim.
// É o número exato de cada ponto, sem depender do mouse.
const props = defineProps({
  painel: { type: Object, required: true },
});

const { t, n, data } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.PERIODO';
const ordem = ref({ coluna: 'inicio', sentido: 'asc' });

const porSemana = computed(() => props.painel.evolucao?.unidade === 'semana');
const anuncios = computed(() => Boolean(props.painel.meta?.anuncios_ligados));
const nomes = computed(() => props.painel.meta?.nomes || {});
const pontos = computed(() => props.painel.evolucao?.pontos || []);
const temParcial = computed(() => pontos.value.some(ponto => ponto.parcial));

const linhas = computed(() =>
  ordenar(
    pontos.value.map(ponto => ({
      ...ponto,
      chave: ponto.inicio,
      taxa_pct: pctDe(ponto.fecharam, ponto.compra),
    })),
    ordem.value
  )
);
const total = computed(() => totalDoPeriodo(pontos.value));

const colunas = computed(() => [
  {
    id: 'inicio',
    titulo: porSemana.value ? t(`${B}.COL.SEMANA`) : t(`${B}.COL.DIA`),
    ordenavel: true,
  },
  {
    id: 'procuras',
    titulo: t(`${B}.COL.PROCURAS`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  {
    id: 'conversas_novas',
    titulo: t(`${B}.COL.CONVERSAS_NOVAS`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  {
    id: 'compra',
    titulo: nomes.value.compra || t(`${B}.COL.COMPRA`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  {
    id: 'fecharam',
    titulo: nomes.value.fechou || t(`${B}.COL.FECHARAM`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  {
    id: 'taxa_pct',
    titulo: t(`${B}.COL.TAXA`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'pct',
  },
  {
    id: 'precisavam_pessoa',
    titulo: t(`${B}.COL.PRECISAVAM`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  {
    id: 'tiveram_pessoa',
    titulo: t(`${B}.COL.TIVERAM`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  ...(anuncios.value
    ? [
        {
          id: 'com_anuncio',
          titulo: t(`${B}.COL.COM_ANUNCIO`),
          alinhar: 'fim',
          ordenavel: true,
          formato: 'numero',
        },
        {
          id: 'sem_anuncio',
          titulo: t(`${B}.COL.SEM_ANUNCIO`),
          alinhar: 'fim',
          ordenavel: true,
          formato: 'numero',
        },
      ]
    : []),
]);
</script>

<template>
  <CartaoDoPainel
    :titulo="porSemana ? t(`${B}.TITULO_SEMANA`) : t(`${B}.TITULO_DIA`)"
    :descricao="t(`${B}.DESCRICAO`)"
    :unidade="t(`${B}.UNIDADE`)"
  >
    <TabelaDoPainel
      :colunas="colunas"
      :linhas="linhas"
      :ordem="ordem"
      :total="total"
      :total-titulo="t(`${B}.TOTAL`)"
      :legenda="porSemana ? t(`${B}.TITULO_SEMANA`) : t(`${B}.TITULO_DIA`)"
      :largura-minima="anuncios ? 'min-w-[56rem]' : 'min-w-[48rem]'"
      @ordenar="ordem = $event"
    >
      <template #celula-inicio="{ linha }">
        <span class="whitespace-nowrap tabular-nums">
          {{
            porSemana
              ? t(`${B}.SEMANA_DE`, { data: data(linha.inicio) })
              : data(linha.inicio)
          }}<span v-if="linha.parcial" class="text-n-amber-11">{{
            t('AGENTS.DESEMPENHO2.A.COMUM.MARCA_PARCIAL')
          }}</span>
        </span>
      </template>
      <template #celula-fecharam="{ valor }">
        <span class="font-semibold text-n-teal-11">{{ n(valor) }}</span>
      </template>
    </TabelaDoPainel>
    <p v-if="temParcial" class="text-xs text-n-slate-11" data-nota-parcial>
      {{ porSemana ? t(`${B}.PARCIAL_SEMANA`) : t(`${B}.PARCIAL_DIA`) }}
    </p>
  </CartaoDoPainel>
</template>
