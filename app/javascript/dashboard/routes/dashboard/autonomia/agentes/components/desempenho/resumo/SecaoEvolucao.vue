<script setup>
import { computed, ref, watch } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { corDe } from '../../../utils/desempenhoCores';
import { indiceDoPico } from '../../../utils/desempenhoGrafico';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import MiniEstatistica from '../comum/MiniEstatistica.vue';
import Segmento from '../comum/Segmento.vue';
import GraficoEvolucao from './GraficoEvolucao.vue';

// #2226 v2 (§2.2) — como o movimento mudou no período: 3 visões (geral, resultado e, com anúncio
// rastreado, origem), legenda em pílulas, total, pico com a data e média por dia (ou semana). Embaixo
// do gráfico, as faixas de quem fechou, quem passou para uma pessoa e quem ficou sem.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.EVOLUCAO';
const DIAS_DA_SEMANA = 7;

const visao = ref('geral');
const anuncios = computed(() => Boolean(props.painel.meta.anuncios_ligados));
watch(anuncios, ligado => {
  if (!ligado && visao.value === 'origem') visao.value = 'geral';
});

const pontos = computed(() => props.painel.evolucao?.pontos || []);
const unidade = computed(() => props.painel.evolucao?.unidade || 'dia');
const nomes = computed(() => props.painel.meta.nomes);
const campo = nome => pontos.value.map(ponto => ponto[nome] || 0);

const opcoes = computed(() => [
  { value: 'geral', label: fmt.t(`${NS}.VISAO.GERAL`) },
  { value: 'resultado', label: fmt.t(`${NS}.VISAO.RESULTADO`) },
  ...(anuncios.value
    ? [{ value: 'origem', label: fmt.t(`${NS}.VISAO.ORIGEM`) }]
    : []),
]);

const SERIES = {
  procuras: { cor: 'volume', nome: () => fmt.t(`${NS}.SERIE.PROCURAS`) },
  compra: { cor: 'preparo', nome: () => nomes.value.compra },
  fecharam: { cor: 'resultado', nome: () => nomes.value.fechou },
  com_anuncio: {
    cor: 'resultado',
    nome: () => fmt.t(`${NS}.SERIE.COM_ANUNCIO`),
  },
  sem_anuncio: { cor: 'volume', nome: () => fmt.t(`${NS}.SERIE.SEM_ANUNCIO`) },
};
const CAMPOS_DA_VISAO = {
  geral: ['procuras', 'compra'],
  resultado: ['compra', 'fecharam'],
  origem: ['com_anuncio', 'sem_anuncio'],
};

const series = computed(() =>
  CAMPOS_DA_VISAO[visao.value].map(id => ({
    id,
    nome: SERIES[id].nome(),
    cor: SERIES[id].cor,
    valores: campo(id),
  }))
);

const faixas = computed(() => [
  {
    id: 'fecharam',
    nome: nomes.value.fechou,
    cor: 'resultado',
    valores: campo('fecharam'),
  },
  {
    id: 'tiveram_pessoa',
    nome: fmt.t(`${NS}.FAIXA.TIVERAM_PESSOA`),
    cor: 'tempo',
    valores: campo('tiveram_pessoa'),
  },
  {
    id: 'sem_pessoa',
    nome: fmt.t(`${NS}.FAIXA.SEM_PESSOA`),
    cor: 'alerta',
    valores: pontos.value.map(ponto =>
      Math.max(0, (ponto.precisavam_pessoa || 0) - (ponto.tiveram_pessoa || 0))
    ),
  },
]);

const principal = computed(() => series.value[0]);
const soma = computed(() =>
  principal.value.valores.reduce((acc, valor) => acc + valor, 0)
);
const pico = computed(() => indiceDoPico(principal.value.valores));
const unidadeTexto = computed(() =>
  fmt.t(`${NS}.UNIDADE.${unidade.value.toUpperCase()}`)
);
const estatisticas = computed(() => {
  const lista = [
    {
      id: 'total',
      valor: fmt.n(soma.value),
      legenda: fmt.t(`${NS}.TOTAL`, { serie: principal.value.nome }),
    },
  ];
  if (pico.value >= 0) {
    lista.push({
      id: 'pico',
      valor: fmt.n(principal.value.valores[pico.value]),
      legenda: fmt.t(`${NS}.PICO.${unidade.value.toUpperCase()}`, {
        data: fmt.data(pontos.value[pico.value].inicio),
      }),
    });
  }
  // A média usa os dias do período (semana cortada no começo ou no fim não puxa a média para baixo).
  const dias = props.painel.meta.periodo?.dias || 0;
  if (pontos.value.length && dias) {
    const porUnidade = unidade.value === 'semana' ? DIAS_DA_SEMANA : 1;
    lista.push({
      id: 'media',
      valor: fmt.decimal((soma.value / dias) * porUnidade),
      legenda: fmt.t(`${NS}.MEDIA`, { unidade: unidadeTexto.value }),
    });
  }
  return lista;
});
</script>

<template>
  <section
    id="evolucao"
    :aria-label="fmt.t(`${NS}.TITULO`)"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CartaoDoPainel
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO.${unidade.toUpperCase()}`)"
    >
      <template #acoes>
        <Segmento
          v-model="visao"
          :opcoes="opcoes"
          :rotulo="fmt.t(`${NS}.VISAO.ROTULO`)"
        />
      </template>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <ul
          data-legenda
          class="flex flex-wrap items-center gap-2 p-0 m-0 list-none"
        >
          <li
            v-for="serie in series"
            :key="serie.id"
            class="flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-full bg-n-alpha-1 text-n-slate-12"
          >
            <span
              class="rounded-full size-2.5"
              :class="corDe(serie.cor).fundo"
              aria-hidden="true"
            />
            {{ serie.nome }}
          </li>
        </ul>
        <div class="grid grid-cols-3 gap-2 sm:flex sm:flex-wrap">
          <MiniEstatistica
            v-for="item in estatisticas"
            :key="item.id"
            :data-estatistica="item.id"
            :valor="item.valor"
            :legenda="item.legenda"
          />
        </div>
      </div>
      <p v-if="!pontos.length" class="m-0 text-sm text-n-slate-11">
        {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.NADA_NO_PERIODO') }}
      </p>
      <GraficoEvolucao
        v-else
        :pontos="pontos"
        :series="series"
        :faixas="faixas"
        :unidade="unidade"
      />
    </CartaoDoPainel>
  </section>
</template>
