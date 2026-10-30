<script setup>
import { computed } from 'vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import {
  BORDA_DE_CIMA,
  COR_DA_FRENTE,
  corDe,
} from '../../../utils/desempenhoCores';
import { nomeCurtoDoAgente } from '../../../utils/desempenhoContrato';
import CabecalhoDeSecao from '../comum/CabecalhoDeSecao.vue';
import LinkDaConversa from '../comum/LinkDaConversa.vue';

// #2226 v2 (§2.11) — do sinal à ação: um cartão por sugestão, com a frente (cor), o problema, a
// prova (números e conversas), o que mudar na instrução e no sistema e o ganho estimado com a conta e
// as datas dele. O valor típico de uma venda (base do ganho em dinheiro) aparece uma vez, no topo.
// Embaixo, só o que precisa de mais dado (o que já dá para usar são os próprios cartões). Na
// demonstração não há botão: cada cartão terá no máximo 1, e só quando existir destino real (ESPEC 2.9).
const props = defineProps({
  painel: { type: Object, required: true },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.ACOES';
const LIMITE = 8;

const nome = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta.agente?.nome,
    fmt.t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);
const frenteDe = item =>
  fmt.tSeTiver(
    `${NS}.FRENTE.${String(item.frente).toUpperCase()}`,
    item.frente,
    { nome: nome.value }
  );
const baseDoTicket = computed(() => {
  const ticket = props.painel.ticket;
  if (!ticket?.com_valor) return '';
  return fmt.t(`${NS}.BASE_DO_TICKET`, {
    valor: fmt.dinheiro(ticket.mediano ?? ticket.medio, ticket.moeda),
    n: fmt.n(ticket.com_valor),
  });
});

const recomendacoes = computed(() =>
  (props.painel.recomendacoes || []).slice(0, LIMITE).map(item => ({
    ...item,
    cor: COR_DA_FRENTE[item.frente] || 'neutro',
  }))
);
const temValor = computed(() =>
  recomendacoes.value.some(item => item.ganho?.valor != null)
);
const faltaDado = computed(() =>
  recomendacoes.value.filter(item => item.pronto === 'falta_dado')
);

// #2301 — sem as sugestões do período exato, vão as últimas do mesmo período, com as datas delas.
const deOutrasDatas = computed(() => {
  const datas = props.painel.meta?.recomendacoes_de;
  if (!datas || !recomendacoes.value.length) return '';
  return fmt.t(`${NS}.DE_OUTRAS_DATAS`, {
    inicio: fmt.data(datas.inicio),
    fim: fmt.data(datas.fim),
  });
});

const ganhoDe = item => fmt.fraseDoGanho(item.ganho, props.painel);
</script>

<template>
  <section
    id="acoes"
    aria-labelledby="acoes-titulo"
    class="flex flex-col gap-4 scroll-mt-28"
  >
    <CabecalhoDeSecao
      id="acoes-titulo"
      :sobre="fmt.t(`${NS}.SOBRE`)"
      :titulo="fmt.t(`${NS}.TITULO`)"
      :descricao="fmt.t(`${NS}.DESCRICAO`)"
    />
    <p
      v-if="temValor && baseDoTicket"
      data-base-do-ticket
      class="flex flex-wrap items-center gap-1.5 m-0 text-xs text-n-slate-11"
    >
      {{ baseDoTicket }}
    </p>
    <p
      v-if="deOutrasDatas"
      data-acoes-outras-datas
      class="m-0 text-xs text-n-slate-11"
    >
      {{ deOutrasDatas }}
    </p>
    <p v-if="!recomendacoes.length" class="m-0 text-sm text-n-slate-11">
      {{ fmt.t(`${NS}.NENHUMA`) }}
    </p>
    <ul
      v-else
      class="grid gap-4 p-0 m-0 list-none md:grid-cols-2 2xl:grid-cols-4"
    >
      <li
        v-for="item in recomendacoes"
        :key="item.id"
        data-acao
        :data-frente="item.frente"
        class="flex flex-col gap-3 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-n-weak dark:shadow-none"
        :class="BORDA_DE_CIMA[item.cor]"
      >
        <span
          class="flex items-center gap-1.5 text-xs font-semibold"
          :class="corDe(item.cor).texto"
        >
          <span
            class="rounded-full size-2"
            :class="corDe(item.cor).fundo"
            aria-hidden="true"
          />
          {{ frenteDe(item) }}
        </span>
        <h3 class="m-0 text-sm font-semibold text-n-slate-12">
          {{ item.titulo }}
        </h3>
        <p class="m-0 text-xs text-n-slate-11">{{ item.problema }}</p>
        <div class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1">
          <span class="text-xs font-semibold text-n-slate-12">{{
            fmt.t(`${NS}.PROVA`)
          }}</span>
          <p class="m-0 text-xs text-n-slate-12 tabular-nums">
            {{ item.numeros }}
          </p>
          <ul
            v-if="item.conversas?.length"
            class="flex flex-col p-0 m-0 list-none"
          >
            <li
              v-for="prova in item.conversas"
              :key="`${prova.conversa}-${prova.procura}`"
            >
              <LinkDaConversa :prova="prova" />
            </li>
          </ul>
        </div>
        <div
          v-if="item.instrucao || item.sistema || item.equipe"
          class="flex flex-col gap-1"
        >
          <span class="text-xs font-semibold text-n-slate-12">{{
            fmt.t(`${NS}.O_QUE_MUDAR`)
          }}</span>
          <p
            v-if="item.instrucao"
            data-na-instrucao
            class="m-0 text-xs text-n-slate-12"
          >
            <strong class="font-semibold">{{
              fmt.t(`${NS}.NA_INSTRUCAO`)
            }}</strong>
            {{ item.instrucao }}
          </p>
          <p
            v-if="item.sistema"
            data-no-sistema
            class="m-0 text-xs text-n-slate-12"
          >
            <strong class="font-semibold">{{
              fmt.t(`${NS}.NO_SISTEMA`)
            }}</strong>
            {{ item.sistema }}
          </p>
          <p
            v-if="item.equipe"
            data-na-equipe
            class="m-0 text-xs text-n-slate-12"
          >
            <strong class="font-semibold">{{
              fmt.t(`${NS}.NA_EQUIPE`)
            }}</strong>
            {{ item.equipe }}
          </p>
        </div>
        <div class="flex flex-col gap-0.5 pt-2 mt-auto border-t border-n-weak">
          <p
            class="flex flex-wrap items-center gap-x-1.5 gap-y-1 m-0 text-xs tabular-nums text-n-slate-12"
          >
            <strong class="font-semibold">{{ fmt.t(`${NS}.GANHO`) }}</strong>
            {{ ganhoDe(item) || fmt.t(`${NS}.GANHO_SEM_CONTA`) }}
            <span
              v-if="item.ganho?.historico"
              data-ganho-historico
              class="px-2 py-0.5 rounded-full bg-n-alpha-2 font-semibold text-n-slate-11"
            >
              {{ fmt.t('AGENTS.DESEMPENHO2.A.COMUM.HISTORICO_COMPLETO') }}
            </span>
          </p>
          <details v-if="item.ganho?.conta" class="group">
            <summary
              class="flex items-center gap-1 text-xs font-semibold list-none cursor-pointer min-h-11 w-fit text-n-blue-11 [&::-webkit-details-marker]:hidden"
            >
              <span
                class="transition-transform i-lucide-chevron-right size-3.5 group-open:rotate-90"
                aria-hidden="true"
              />
              {{ fmt.t(`${NS}.COMO_CALCULAMOS`) }}
            </summary>
            <p class="m-0 text-xs text-n-slate-11">{{ item.ganho.conta }}</p>
          </details>
        </div>
      </li>
    </ul>
    <div
      v-if="faltaDado.length"
      data-coluna="falta_dado"
      class="flex flex-col gap-2 p-5 shadow-sm rounded-2xl bg-n-solid-1 ring-1 ring-n-weak dark:shadow-none"
      :class="BORDA_DE_CIMA.tempo"
    >
      <h3 class="m-0 text-sm font-semibold" :class="corDe('tempo').texto">
        {{ fmt.t(`${NS}.COLUNA.FALTA_DADO`) }}
      </h3>
      <ul class="flex flex-col gap-1.5 p-0 m-0 list-none">
        <li
          v-for="item in faltaDado"
          :key="item.id"
          class="flex flex-col text-sm text-n-slate-12"
        >
          {{ item.titulo }}
          <span v-if="item.falta" class="text-xs text-n-slate-11">
            {{ fmt.t(`${NS}.FALTA`, { falta: item.falta }) }}
          </span>
        </li>
      </ul>
    </div>
  </section>
</template>
