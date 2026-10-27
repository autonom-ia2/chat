<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import LinkDaConversa from '../comum/LinkDaConversa.vue';
import MiniEstatistica from '../comum/MiniEstatistica.vue';
import RankingDeBarras from '../comum/RankingDeBarras.vue';
import Ressalva from '../comum/Ressalva.vue';
import { nomeCurtoDoAgente } from '../../../utils/desempenhoContrato';

// #2226 v2 (§2.8) — quem precisava de uma pessoa da equipe e se teve: quantas ficaram sem, sobre o
// que eram, como terminaram, quantas chegaram fora do horário e as conversas de exemplo. A série de
// mensagens da equipe por mês vale para o histórico inteiro (o selo diz), não para o período.
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.PESSOA';

const pessoa = computed(() => props.painel.pessoa || {});
const nome = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta.agente?.nome,
    fmt.t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);
const comValor = lista =>
  (lista || []).map(item => ({ ...item, valor: item.n, pct: null }));
const equipePorMes = computed(() =>
  (pessoa.value.equipe_por_mes || []).map(item => ({
    id: item.mes,
    nome: fmt.mes(item.mes),
    valor: item.n,
    pct: null,
  }))
);

const estatisticas = computed(() => [
  {
    id: 'precisavam',
    valor: fmt.n(pessoa.value.precisavam),
    legenda: fmt.t(`${NS}.PRECISAVAM`),
  },
  {
    id: 'tiveram',
    valor: fmt.n(pessoa.value.tiveram),
    legenda: fmt.t(`${NS}.TIVERAM`),
    cor: 'resultado',
  },
  {
    id: 'sem_pessoa',
    valor: `${fmt.n(pessoa.value.sem_pessoa)} (${fmt.pct(pessoa.value.sem_pessoa_pct)})`,
    legenda: fmt.t(`${NS}.FICARAM_SEM`),
    cor: 'alerta',
  },
  {
    id: 'prometida',
    valor: fmt.t(`${NS}.N_DE_M`, {
      n: fmt.n(pessoa.value.prometida_sem_resposta),
      m: fmt.n(pessoa.value.prometida),
    }),
    legenda: fmt.t(`${NS}.PROMETEU`),
    cor: 'tempo',
  },
]);
</script>

<template>
  <section
    id="pessoa"
    aria-labelledby="pessoa-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="pessoa-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <div class="grid grid-cols-2 gap-3 md:grid-cols-4">
      <MiniEstatistica
        v-for="item in estatisticas"
        :key="item.id"
        :data-estatistica="item.id"
        :valor="item.valor"
        :legenda="item.legenda"
        :cor="item.cor || ''"
      />
    </div>
    <div class="grid items-start gap-4 xl:grid-cols-3">
      <CartaoDoPainel
        :titulo="fmt.t(`${NS}.SOBRE_O_QUE`)"
        :unidade="fmt.t(`${NS}.UNIDADE`)"
      >
        <RankingDeBarras
          :itens="comValor(pessoa.por_pedido)"
          cor="alerta"
          :rotulo="fmt.t(`${NS}.SOBRE_O_QUE`)"
        />
      </CartaoDoPainel>
      <CartaoDoPainel
        :titulo="fmt.t(`${NS}.COMO_TERMINOU`)"
        :unidade="fmt.t(`${NS}.UNIDADE`)"
      >
        <RankingDeBarras
          :itens="comValor(pessoa.por_resultado)"
          cor="neutro"
          :rotulo="fmt.t(`${NS}.COMO_TERMINOU`)"
        />
      </CartaoDoPainel>
      <CartaoDoPainel
        v-if="equipePorMes.length"
        data-equipe-por-mes
        :titulo="fmt.t(`${NS}.EQUIPE_POR_MES`)"
        :descricao="fmt.t(`${NS}.EQUIPE_POR_MES_DESCRICAO`)"
        :unidade="fmt.t(`${NS}.UNIDADE_EQUIPE`)"
      >
        <template #acoes>
          <span
            data-historico-completo
            class="px-2 py-0.5 text-xs font-semibold rounded-full bg-n-alpha-2 text-n-slate-11"
          >
            {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.HISTORICO_COMPLETO') }}
          </span>
        </template>
        <RankingDeBarras
          :itens="equipePorMes"
          cor="volume"
          :limite="12"
          :rotulo="fmt.t(`${NS}.EQUIPE_POR_MES`)"
        />
        <Ressalva
          data-conta-do-agente
          :texto="fmt.t(`${NS}.CONTA_DO_AGENTE`, { nome })"
        />
      </CartaoDoPainel>
    </div>
    <p
      v-if="pessoa.sem_pessoa"
      data-fora-do-horario
      class="flex items-center gap-2 m-0 text-sm text-n-slate-12 tabular-nums"
    >
      <span
        class="i-lucide-moon size-4 shrink-0 text-n-amber-11"
        aria-hidden="true"
      />
      {{
        fmt.t(`${NS}.FORA_DO_HORARIO`, {
          n: fmt.n(pessoa.sem_pessoa_fora_do_horario),
          m: fmt.n(pessoa.sem_pessoa),
        })
      }}
    </p>
    <div v-if="pessoa.exemplos?.length" class="flex flex-col gap-1">
      <p class="m-0 text-xs font-semibold text-n-slate-11">
        {{ fmt.t(`${NS}.EXEMPLOS`) }}
      </p>
      <ul class="grid gap-x-6 p-0 m-0 list-none md:grid-cols-3">
        <li
          v-for="prova in pessoa.exemplos.slice(0, 3)"
          :key="`${prova.conversa}-${prova.procura}`"
        >
          <LinkDaConversa :prova="prova" com-resumo />
        </li>
      </ul>
    </div>
  </section>
</template>
