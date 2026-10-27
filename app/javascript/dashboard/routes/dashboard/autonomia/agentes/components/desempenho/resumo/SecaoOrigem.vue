<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { BORDA_DE_CIMA, corDe } from '../../../utils/desempenhoCores';
import {
  MINIMO_DA_TAXA,
  pct as pctDe,
  poucosCasos,
} from '../../../utils/desempenhoContrato';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import RankingDeBarras from '../comum/RankingDeBarras.vue';
import Ressalva from '../comum/Ressalva.vue';
import RessalvasDaConferencia from '../comum/RessalvasDaConferencia.vue';

// #2226 v2 (§4) — de onde vêm as procuras, sempre visível. Sem anúncio rastreado (a): como chegaram
// e quem fecha mais, com a frase calma e, para admin, o link discreto para ligar anúncios. Com
// anúncios (b): "Veio de anúncio × Chegou sem anúncio" com a MESMA métrica lado a lado, o ranking por
// anúncio e, ao lado, como chegaram os que vieram sem anúncio. Os nomes dos grupos vêm dos dados.
const props = defineProps({
  painel: { type: Object, required: true },
  ehAdmin: { type: Boolean, default: false },
  hrefLigarAnuncios: { type: String, default: '' },
});

const emit = defineEmits(['ligarAnuncios']);

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.ORIGEM';
// O grupo "não sabemos de onde veio": marcado no dado (`desconhecida: true`) ou, até o contrato
// trazer a marca, pelos ids usados hoje no catálogo de origens. E o limite para avisar.
const ORIGENS_DESCONHECIDAS = ['desconhecida', 'organico_desconhecido'];
const LIMITE_DESCONHECIDA = 50;

const origem = computed(
  () => props.painel.origem || { grupos: [], anuncios: [] }
);
const comAnuncios = computed(() =>
  Boolean(origem.value.anuncios_ligados && origem.value.comparacao)
);
const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);
const compra = computed(() => minusculo(props.painel.meta.nomes.compra));
const fechou = computed(() => minusculo(props.painel.meta.nomes.fechou));

const linhaDoGrupo = grupo => ({ ...grupo, valor: grupo.procuras });
const grupos = computed(() => (origem.value.grupos || []).map(linhaDoGrupo));
const gruposSemAnuncio = computed(() =>
  grupos.value.filter(grupo => grupo.tipo === 'sem_anuncio')
);

// "25,6% fecharam (10 de 39 cotações…)"; com menos de 5 pedidos de compra, só a contagem e o aviso.
// A comparação "quantas vezes mais" fica só no bloco "O que muda o resultado", com a conta exata.
const fraseDoGrupo = grupo => {
  if (!grupo.compra) return '';
  const valores = {
    pct: fmt.pct(grupo.taxa_pct),
    n: fmt.n(grupo.fecharam),
    m: fmt.n(grupo.compra),
    compra: compra.value,
    fechou: fechou.value,
  };
  return poucosCasos(grupo.compra)
    ? fmt.t(`${NS}.FECHAM_POUCOS`, valores)
    : fmt.t(`${NS}.FECHAM`, valores);
};

const desconhecidaDemais = computed(() => {
  const grupo = (origem.value.grupos || []).find(
    item =>
      item.desconhecida === true || ORIGENS_DESCONHECIDAS.includes(item.id)
  );
  return Boolean(grupo && grupo.pct > LIMITE_DESCONHECIDA);
});

const lados = computed(() => {
  const { comparacao } = origem.value;
  if (!comparacao) return [];
  const total =
    (comparacao.anuncio.procuras || 0) + (comparacao.sem_anuncio.procuras || 0);
  // Pela conta exata de cada lado (não pelos % arredondados); base pequena não compara.
  const { anuncio, sem_anuncio: semAnuncio } = comparacao;
  const comparavel =
    anuncio.compra >= MINIMO_DA_TAXA &&
    semAnuncio.compra >= MINIMO_DA_TAXA &&
    semAnuncio.fecharam > 0;
  const vezes = comparavel
    ? anuncio.fecharam /
      anuncio.compra /
      (semAnuncio.fecharam / semAnuncio.compra)
    : null;
  return [
    {
      id: 'anuncio',
      cor: 'resultado',
      dados: comparacao.anuncio,
      total,
      vezes,
    },
    {
      id: 'sem_anuncio',
      cor: 'volume',
      dados: comparacao.sem_anuncio,
      total,
      vezes: null,
    },
  ];
});

const anuncios = computed(() =>
  (origem.value.anuncios || []).map(anuncio => ({
    ...anuncio,
    valor: anuncio.procuras,
    pct: null,
  }))
);
const fraseDoAnuncio = anuncio =>
  [
    anuncio.campanha,
    fmt.t(`${NS}.FECHARAM`, {
      n: fmt.n(anuncio.fecharam),
      fechou: fechou.value,
    }),
    fmt.pct(anuncio.taxa_pct),
    anuncio.custo_por_fechou !== null && anuncio.custo_por_fechou !== undefined
      ? fmt.t(`${NS}.CUSTO_POR_FECHOU`, {
          valor: fmt.dinheiro(anuncio.custo_por_fechou),
        })
      : '',
  ]
    .filter(Boolean)
    .join(' · ');
</script>

<template>
  <section
    id="origem"
    aria-labelledby="origem-titulo"
    :data-estado-origem="comAnuncios ? 'com_anuncio' : 'sem_anuncio'"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="origem-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />

    <template v-if="comAnuncios">
      <div data-anuncio-x-sem class="grid gap-4 md:grid-cols-2">
        <article
          v-for="lado in lados"
          :key="lado.id"
          :data-lado="lado.id"
          class="flex flex-col gap-2 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-n-weak dark:shadow-none"
          :class="BORDA_DE_CIMA[lado.cor]"
        >
          <h3 class="m-0 text-sm font-semibold" :class="corDe(lado.cor).texto">
            {{ fmt.t(`${NS}.LADO.${lado.id.toUpperCase()}`) }}
          </h3>
          <p class="m-0 text-sm tabular-nums text-n-slate-12">
            <strong class="text-2xl font-bold">{{
              fmt.n(lado.dados.procuras)
            }}</strong>
            {{
              fmt.t(`${NS}.PROCURAS_PCT`, {
                pct: fmt.pct(pctDe(lado.dados.procuras, lado.total)),
              })
            }}
          </p>
          <p class="m-0 text-xs tabular-nums text-n-slate-11">
            {{
              fmt.t(`${NS}.COMPRA_E_FECHARAM`, {
                compra: fmt.n(lado.dados.compra),
                nome: compra,
                fecharam: fmt.n(lado.dados.fecharam),
                fechou,
              })
            }}
          </p>
          <p class="flex flex-wrap items-baseline gap-2 m-0 tabular-nums">
            <span
              class="text-3xl font-bold leading-none"
              :class="corDe(lado.cor).texto"
            >
              {{ fmt.pct(lado.dados.taxa_pct) }}
            </span>
            <span class="text-sm text-n-slate-11">
              {{ fmt.t(`${NS}.TAXA`, { fechou }) }}
            </span>
            <span
              v-if="lado.vezes"
              data-vezes
              class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-alpha-2 text-n-slate-12"
            >
              {{ fmt.t(`${NS}.VEZES`, { x: fmt.decimal(lado.vezes) }) }}
            </span>
          </p>
        </article>
      </div>
      <div class="grid items-start gap-4 xl:grid-cols-[1.45fr_1fr]">
        <CartaoDoPainel
          data-por-anuncio
          :titulo="fmt.t(`${NS}.POR_ANUNCIO`)"
          :descricao="fmt.t(`${NS}.POR_ANUNCIO_DESCRICAO`)"
          :unidade="fmt.t(`${NS}.UNIDADE`)"
        >
          <RankingDeBarras
            :itens="anuncios"
            cor="resultado"
            :rotulo="fmt.t(`${NS}.POR_ANUNCIO`)"
          >
            <template #extra="{ item }">{{ fraseDoAnuncio(item) }}</template>
          </RankingDeBarras>
          <p
            v-if="origem.sem_saber_qual"
            class="m-0 text-xs tabular-nums text-n-slate-11"
          >
            {{
              fmt.t(`${NS}.SEM_SABER_QUAL`, { n: fmt.n(origem.sem_saber_qual) })
            }}
          </p>
        </CartaoDoPainel>
        <CartaoDoPainel
          :titulo="fmt.t(`${NS}.SEM_ANUNCIO_CHEGARAM`)"
          :unidade="fmt.t(`${NS}.UNIDADE`)"
        >
          <RankingDeBarras
            :itens="gruposSemAnuncio"
            cor="volume"
            :rotulo="fmt.t(`${NS}.SEM_ANUNCIO_CHEGARAM`)"
          >
            <template #extra="{ item }">{{ fraseDoGrupo(item) }}</template>
          </RankingDeBarras>
        </CartaoDoPainel>
      </div>
      <Ressalva
        :destaque="origem.nota || ''"
        :texto="fmt.t(`${NS}.DIRECT_FORA`)"
      />
    </template>

    <template v-else>
      <div class="grid items-start gap-4 xl:grid-cols-[1.45fr_1fr]">
        <CartaoDoPainel
          data-como-chegaram
          :titulo="fmt.t(`${NS}.COMO_CHEGARAM`)"
          :descricao="fmt.t(`${NS}.COMO_CHEGARAM_DESCRICAO`)"
          :unidade="fmt.t(`${NS}.UNIDADE`)"
        >
          <RankingDeBarras
            :itens="grupos"
            cor="volume"
            :rotulo="fmt.t(`${NS}.COMO_CHEGARAM`)"
          >
            <template #extra="{ item }">{{ fraseDoGrupo(item) }}</template>
          </RankingDeBarras>
        </CartaoDoPainel>
        <div class="flex flex-col gap-3">
          <p
            data-sem-anuncio
            class="flex flex-wrap items-center gap-x-3 gap-y-1 m-0 text-sm text-n-slate-11"
          >
            <span class="flex items-center gap-2">
              <span class="i-lucide-info size-4 shrink-0" aria-hidden="true" />
              {{ fmt.t(`${NS}.SEM_ANUNCIO_FRASE`) }}
            </span>
            <a
              v-if="ehAdmin && hrefLigarAnuncios"
              data-ligar-anuncios
              :href="hrefLigarAnuncios"
              class="inline-flex items-center font-semibold rounded-md min-h-11 text-n-blue-11 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
              @click.prevent="emit('ligarAnuncios')"
            >
              {{ fmt.t(`${NS}.LIGAR_ANUNCIOS`) }}
            </a>
          </p>
          <RessalvasDaConferencia :painel="painel" parte="origem" />
          <Ressalva
            v-if="origem.nota || desconhecidaDemais"
            :destaque="
              desconhecidaDemais ? fmt.t(`${NS}.MAIORIA_NAO_DISSE`) : ''
            "
            :texto="origem.nota || ''"
          />
        </div>
      </div>
    </template>
  </section>
</template>
