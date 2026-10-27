<script setup>
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import TabelaDoPainel from './TabelaDoPainel.vue';
import Paginacao from './Paginacao.vue';
import FiltrosDasProcuras from './FiltrosDasProcuras.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  COR,
  COR_DO_GRUPO,
  COR_DA_QUALIDADE,
} from '../../../utils/desempenhoCores';
import {
  diaDe,
  hrefDaConversa,
  nomeCurtoDoAgente,
} from '../../../utils/desempenhoContrato';
import {
  enderecoDaAba,
  filtrarProcuras,
  filtrosDoEndereco,
  filtrosValidos,
  linhaDaProcura,
  opcoesDosFiltros,
  ordenar,
  paginar,
  resumoDasProcuras,
} from '../../../utils/desempenhoDetalhe';

// #2226 v2 — todas as procuras do período, com busca, filtros, ordenação e página. Os filtros
// vivem no endereço (o Resumo traz a pessoa já filtrada); a ordem fica só na tela.
const props = defineProps({
  painel: { type: Object, required: true },
});

const route = useRoute();
const router = useRouter();
const { t, tSeTiver, n, pct, data, hora } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.PROCURAS';
// O nome da IA no cabeçalho da coluna de qualidade: "agente", nos dados, também é quem escreve.
const nomeDaIa = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta?.agente?.nome,
    t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);

const opcoes = computed(() => opcoesDosFiltros(props.painel, t));
const doEndereco = () =>
  filtrosValidos(filtrosDoEndereco(route.query), opcoes.value);
const filtros = ref(doEndereco());
const ordem = ref({ coluna: 'inicio', sentido: 'desc' });
const abertas = ref([]);

const mesmos = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// Voltar/avançar no navegador ou um link do Resumo trocam o endereço: a tela acompanha.
watch(
  () => route.query,
  () => {
    const novos = doEndereco();
    if (!mesmos(novos, filtros.value)) filtros.value = novos;
  }
);

watch(
  filtros,
  novos => {
    const query = enderecoDaAba(route.query, 'procuras', novos);
    if (!mesmos(query, route.query)) router.replace({ query });
  },
  { deep: true }
);

// Qualquer filtro novo volta para a página 1.
const mudarFiltros = novos => {
  filtros.value = { ...novos, pagina: 1 };
};
const mudarPagina = pagina => {
  filtros.value = { ...filtros.value, pagina };
};
const mudarTamanho = tamanho => {
  filtros.value = { ...filtros.value, tamanho, pagina: 1 };
};

const etapas = computed(() => props.painel.funil?.etapas || []);
const filtradas = computed(() =>
  filtrarProcuras(
    props.painel.procuras || [],
    filtros.value,
    props.painel.catalogo,
    etapas.value
  )
);
const contagem = computed(() =>
  resumoDasProcuras(filtradas.value, props.painel.catalogo)
);
const linhas = computed(() =>
  ordenar(
    filtradas.value.map(procura => linhaDaProcura(procura, props.painel)),
    ordem.value.coluna === 'marco'
      ? { ...ordem.value, coluna: 'marco_ordem' }
      : ordem.value
  )
);
const pagina = computed(() =>
  paginar(linhas.value, filtros.value.pagina, filtros.value.tamanho)
);

const nomeDoFechou = computed(() => props.painel.meta?.nomes?.fechou || '');
const nomeDaCompra = computed(() =>
  String(props.painel.meta?.nomes?.compra || '').toLocaleLowerCase()
);
const semNome = valor => valor || t('AGENTS.DESEMPENHO2.B.SEM_NOME');

const colunas = computed(() => [
  { id: 'inicio', titulo: t(`${B}.COL.QUANDO`), ordenavel: true },
  { id: 'conversa', titulo: t(`${B}.COL.CONVERSA`), ordenavel: true },
  { id: 'tema', titulo: t(`${B}.COL.TEMA`), ordenavel: true },
  {
    id: 'pedido',
    titulo: props.painel.cortes?.[0]?.nome || t(`${B}.COL.PEDIDO`),
    ordenavel: true,
  },
  { id: 'marco', titulo: t(`${B}.COL.MARCO`), ordenavel: true },
  { id: 'resultado', titulo: t(`${B}.COL.RESULTADO`), ordenavel: true },
  {
    id: 'qualidade',
    titulo: t(`${B}.COL.AGENTE`, { nome: nomeDaIa.value }),
    ordenavel: true,
  },
  { id: 'origem', titulo: t(`${B}.COL.ORIGEM`), ordenavel: true },
  { id: 'resumo', titulo: t(`${B}.COL.RESUMO`) },
]);

const hrefDe = linha => hrefDaConversa(router, linha.conversa);
const abrirConversa = linha => {
  if (!linha.visivel) return;
  window.open(hrefDe(linha), '_blank', 'noopener,noreferrer');
};

// "#312", ou "#312·2" quando é a 2ª procura da mesma conversa.
const numeroDaConversa = linha =>
  linha.procura > 1
    ? t(`${B}.NUMERO_E_PROCURA`, { n: linha.conversa, procura: linha.procura })
    : t(`${B}.NUMERO`, { n: linha.conversa });

const corDoGrupo = grupo => COR[COR_DO_GRUPO[grupo]] || COR.neutro;
const corDaQualidade = id => COR[COR_DA_QUALIDADE[id]] || COR.neutro;
// Id de qualidade que o i18n não conhece mostra "Sem nome", nunca a chave crua.
const textoDaQualidade = id =>
  tSeTiver(
    `AGENTS.DESEMPENHO2.B.FILTROS.QUALIDADE.${String(id).toUpperCase()}`,
    t('AGENTS.DESEMPENHO2.B.SEM_NOME')
  );

const alternarResumo = chave => {
  abertas.value = abertas.value.includes(chave)
    ? abertas.value.filter(item => item !== chave)
    : [...abertas.value, chave];
};
</script>

<template>
  <CartaoDoPainel
    :titulo="t(`${B}.TITULO`)"
    :descricao="t(`${B}.DESCRICAO`)"
    :unidade="t(`${B}.UNIDADE`)"
  >
    <FiltrosDasProcuras
      :filtros="filtros"
      :opcoes="opcoes"
      :nome="nomeDaIa"
      @update:filtros="mudarFiltros"
    />
    <p class="text-sm text-n-slate-12 tabular-nums scroll-mt-28" data-contador>
      <span class="font-semibold">{{
        t(`${B}.CONTADOR`, { n: n(contagem.total) })
      }}</span>
      <span class="text-n-slate-11">
        {{ t('AGENTS.DESEMPENHO2.A.COMUM.SEPARADOR') }}
        {{
          t(`${B}.CONTADOR_FECHARAM`, {
            fechou: nomeDoFechou,
            n: n(contagem.fecharam),
            m: n(contagem.compra),
            compra: nomeDaCompra,
            pct: pct(contagem.pct),
          })
        }}
      </span>
    </p>
    <p class="-mt-1 text-xs text-n-slate-11" data-explica-numero>
      {{ t(`${B}.EXPLICA_NUMERO`) }}
    </p>
    <ul
      data-cartoes-celular
      class="flex flex-col gap-2 p-0 m-0 list-none md:hidden"
      :aria-label="t(`${B}.TITULO`)"
    >
      <li
        v-if="!pagina.itens.length"
        class="py-6 text-sm text-center text-n-slate-11"
      >
        {{ t(`${B}.VAZIO`) }}
      </li>
      <li
        v-for="linha in pagina.itens"
        :key="linha.chave"
        :data-cartao-procura="linha.chave"
        class="flex flex-col gap-1.5 p-3 rounded-xl ring-1 ring-n-weak"
      >
        <span class="flex items-center justify-between gap-3">
          <span class="text-xs tabular-nums text-n-slate-11">
            {{ data(diaDe(linha.inicio)) }}
            {{ t('AGENTS.DESEMPENHO2.A.COMUM.SEPARADOR') }}
            {{ hora(linha.inicio) }}
          </span>
          <a
            v-if="linha.visivel"
            :href="hrefDe(linha)"
            target="_blank"
            rel="noopener noreferrer"
            class="inline-flex items-center px-1 font-semibold min-h-11 tabular-nums text-n-blue-11 underline-offset-4 hover:underline"
            :aria-label="t(`${B}.ABRIR_CONVERSA`, { n: linha.conversa })"
          >
            {{ numeroDaConversa(linha) }}
          </a>
          <span v-else class="text-xs text-n-slate-11">{{
            t(`${B}.OUTRA_EQUIPE`)
          }}</span>
        </span>
        <span class="text-sm font-semibold truncate text-n-slate-12">{{
          semNome(linha.tema)
        }}</span>
        <span class="flex flex-wrap items-center gap-1.5">
          <span
            class="inline-flex px-2 py-0.5 rounded-full text-xs font-semibold"
            :class="[
              corDoGrupo(linha.grupo).fundoSuave,
              corDoGrupo(linha.grupo).texto,
            ]"
          >
            {{ semNome(linha.resultado) }}
          </span>
          <span
            v-if="linha.qualidade"
            class="inline-flex px-2 py-0.5 rounded-full text-xs font-semibold"
            :class="[
              corDaQualidade(linha.qualidade).fundoSuave,
              corDaQualidade(linha.qualidade).texto,
            ]"
          >
            {{
              t('AGENTS.DESEMPENHO2.A.COMUM.ROTULO_E_VALOR', {
                rotulo: nomeDaIa,
                valor: textoDaQualidade(linha.qualidade),
              })
            }}
          </span>
        </span>
        <span class="text-xs text-n-slate-11 line-clamp-2">{{
          linha.resumo
        }}</span>
      </li>
    </ul>
    <TabelaDoPainel
      class="hidden md:block"
      :colunas="colunas"
      :linhas="pagina.itens"
      :ordem="ordem"
      :legenda="t(`${B}.TITULO`)"
      :vazio="t(`${B}.VAZIO`)"
      largura-minima="min-w-[64rem]"
      linha-clicavel
      @ordenar="ordem = $event"
      @linha="abrirConversa"
    >
      <template #celula-inicio="{ linha }">
        <span class="flex flex-col whitespace-nowrap tabular-nums">
          <span>{{ data(diaDe(linha.inicio)) }}</span>
          <span class="text-xs text-n-slate-11">{{ hora(linha.inicio) }}</span>
        </span>
      </template>
      <template #celula-conversa="{ linha }">
        <a
          v-if="linha.visivel"
          :href="hrefDe(linha)"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex items-center min-h-11 -my-2.5 font-semibold tabular-nums text-n-blue-11 underline-offset-4 hover:underline whitespace-nowrap"
          :aria-label="t(`${B}.ABRIR_CONVERSA`, { n: linha.conversa })"
          data-link-conversa
        >
          {{ numeroDaConversa(linha) }}
        </a>
        <span v-else class="text-xs text-n-slate-11">{{
          t(`${B}.OUTRA_EQUIPE`)
        }}</span>
        <span
          v-if="linha.teste"
          class="block text-xs text-n-amber-11 whitespace-nowrap"
        >
          {{ t(`${B}.TESTE`) }}
        </span>
      </template>
      <template #celula-tema="{ linha }">
        <span class="block max-w-[12rem] truncate" :title="semNome(linha.tema)">
          {{ semNome(linha.tema) }}
        </span>
      </template>
      <template #celula-pedido="{ linha }">
        <span class="block max-w-[10rem] truncate" :title="linha.pedido || ''">
          {{ linha.pedido || t('AGENTS.DESEMPENHO2.A.COMUM.SEM_VALOR') }}
        </span>
      </template>
      <template #celula-marco="{ linha }">
        <span class="block max-w-[10rem] truncate" :title="linha.marco || ''">{{
          linha.marco || '—'
        }}</span>
      </template>
      <template #celula-resultado="{ linha }">
        <span
          class="inline-flex px-2 py-0.5 rounded-full text-xs font-semibold"
          :class="[
            corDoGrupo(linha.grupo).fundoSuave,
            corDoGrupo(linha.grupo).texto,
          ]"
        >
          {{ semNome(linha.resultado) }}
        </span>
      </template>
      <template #celula-qualidade="{ linha }">
        <span
          v-if="linha.qualidade"
          class="inline-flex px-2 py-0.5 rounded-full text-xs font-semibold whitespace-nowrap"
          :class="[
            corDaQualidade(linha.qualidade).fundoSuave,
            corDaQualidade(linha.qualidade).texto,
          ]"
        >
          {{ textoDaQualidade(linha.qualidade) }}
        </span>
        <span v-else>{{ t('AGENTS.DESEMPENHO2.A.COMUM.SEM_VALOR') }}</span>
      </template>
      <template #celula-origem="{ linha }">
        <span
          class="block max-w-[9rem] truncate"
          :title="semNome(linha.origem)"
        >
          {{ semNome(linha.origem) }}
        </span>
      </template>
      <template #celula-resumo="{ linha }">
        <span class="flex flex-col items-start gap-1 min-w-[16rem]">
          <span
            class="text-n-slate-12"
            :class="{ 'line-clamp-1': !abertas.includes(linha.chave) }"
            :title="linha.resumo"
          >
            {{ linha.resumo }}
          </span>
          <button
            v-if="linha.resumo.length > 60"
            type="button"
            class="min-h-11 -my-3 text-xs text-n-blue-11 hover:underline"
            :aria-expanded="abertas.includes(linha.chave)"
            @click="alternarResumo(linha.chave)"
          >
            {{
              abertas.includes(linha.chave) ? t(`${B}.MENOS`) : t(`${B}.MAIS`)
            }}
          </button>
        </span>
      </template>
    </TabelaDoPainel>
    <Paginacao
      :pagina="pagina"
      :tamanho="filtros.tamanho"
      @update:pagina="mudarPagina"
      @update:tamanho="mudarTamanho"
    />
  </CartaoDoPainel>
</template>
