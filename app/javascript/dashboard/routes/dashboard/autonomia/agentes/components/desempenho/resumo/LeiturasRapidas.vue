<script setup>
import { computed } from 'vue';
import { Translation } from 'vue-i18n';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { corDe } from '../../../utils/desempenhoCores';
import {
  maiorTravaDaCompra,
  sugestaoPrincipal,
} from '../../../utils/desempenhoContrato';
import { ritmoDaSerie } from '../../../utils/desempenhoGrafico';

// #2226 v2 (§2.1) — as leituras rápidas embaixo dos números: só o que os números do topo não dizem
// (mensagens, ritmo, maior trava e por onde começar), uma frase cada, com os números em negrito,
// montada do contrato (sem IA). Leitura sem dado não aparece. A frase inteira é do i18n
// (<Translation>), para cada idioma pôr as palavras na ordem certa.
const props = defineProps({
  painel: { type: Object, required: true },
  agente: { type: String, default: '' },
});

const fmt = useFormatoDoPainel();
const NS = 'AGENTS.DESEMPENHO2.A.LEITURA';
const MUDANCA_MINIMA = 0.2;

const minusculo = texto =>
  String(texto || '').toLocaleLowerCase(fmt.idioma.value);

const leituraDoVolume = () => {
  const { base } = props.painel.meta;
  return {
    id: 'VOLUME',
    cor: 'volume',
    textos: { nome: props.agente },
    numeros: {
      conversas: fmt.n(base.conversas),
      agente: fmt.n(base.mensagens?.agente),
      equipe: fmt.n(base.mensagens?.equipe),
    },
    nota: fmt.t(`${NS}.VOLUME.NOTA`, { nome: props.agente }),
  };
};

const leituraDoRitmo = () => {
  const evolucao = props.painel.evolucao || {};
  const ritmo = ritmoDaSerie(evolucao.pontos || [], 'compra', evolucao.unidade);
  if (!ritmo || !ritmo.antes) return null;
  const mudou = Math.abs(ritmo.depois - ritmo.antes) / ritmo.antes;
  if (mudou < MUDANCA_MINIMA) return null;
  return {
    id: 'RITMO',
    frase: evolucao.unidade === 'dia' ? 'FRASE_DIA' : 'FRASE',
    cor: ritmo.depois < ritmo.antes ? 'alerta' : 'volume',
    textos: {
      compra: props.painel.meta.nomes.compra,
      k: fmt.n(ritmo.semanas),
    },
    numeros: {
      antes: fmt.n(Math.round(ritmo.antes)),
      depois: fmt.n(Math.round(ritmo.depois)),
    },
  };
};

// O mesmo fato que as sugestões usam, na mesma base (as procuras de compra).
const leituraDaTrava = () => {
  const trava = maiorTravaDaCompra(props.painel);
  if (!trava) return null;
  return {
    id: 'TRAVA',
    cor: 'alerta',
    textos: {
      motivo: trava.nome || fmt.t('AGENTS.DESEMPENHO2.A.COMUM.SEM_NOME'),
      compra: minusculo(props.painel.meta.nomes.compra),
    },
    numeros: {
      n: fmt.n(trava.n),
      total: fmt.n(trava.m),
      pct: fmt.pct(trava.pct),
    },
  };
};

const leituraDaDecisao = () => {
  const sugestao = sugestaoPrincipal(props.painel);
  if (!sugestao) return null;
  const vendas = sugestao.ganho?.fechamentos;
  // O ganho vem com as datas dele (e, se a conta usou o histórico completo, dito por extenso).
  const ganho =
    vendas > 0
      ? fmt.fraseDoGanho(sugestao.ganho, props.painel, { comValor: false })
      : '';
  return {
    id: 'DECISAO',
    frase: ganho ? 'FRASE_COM_GANHO' : 'FRASE',
    cor: 'resultado',
    textos: { titulo: sugestao.titulo },
    numeros: ganho ? { ganho } : {},
    ancora: 'acoes',
  };
};

const leituras = computed(() =>
  [
    leituraDoVolume(),
    leituraDoRitmo(),
    leituraDaTrava(),
    leituraDaDecisao(),
  ].filter(Boolean)
);

const rolarAte = id =>
  document
    .getElementById(id)
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
</script>

<template>
  <ul
    data-leituras
    class="grid grid-cols-1 gap-3 p-0 m-0 list-none md:grid-cols-2 xl:grid-cols-4"
  >
    <li
      v-for="leitura in leituras"
      :key="leitura.id"
      :data-leitura="leitura.id"
      class="flex flex-col gap-1 p-3 rounded-xl bg-n-alpha-1"
    >
      <span
        class="flex items-center gap-1.5 text-xs font-semibold"
        :class="corDe(leitura.cor).texto"
      >
        <span
          class="rounded-full size-2"
          :class="corDe(leitura.cor).fundo"
          aria-hidden="true"
        />
        {{ fmt.t(`${NS}.${leitura.id}.TITULO`) }}
      </span>
      <Translation
        :keypath="`${NS}.${leitura.id}.${leitura.frase || 'FRASE'}`"
        tag="p"
        scope="global"
        class="m-0 text-sm text-n-slate-12 tabular-nums"
      >
        <template v-for="(valor, nome) in leitura.textos" :key="nome" #[nome]>
          {{ valor }}
        </template>
        <template v-for="(valor, nome) in leitura.numeros" :key="nome" #[nome]>
          <strong class="font-semibold">{{ valor }}</strong>
        </template>
      </Translation>
      <p v-if="leitura.nota" class="m-0 text-xs text-n-slate-11">
        {{ leitura.nota }}
      </p>
      <button
        v-if="leitura.ancora"
        type="button"
        class="self-start mt-auto text-xs font-semibold rounded-md min-h-11 text-n-blue-11 underline-offset-4 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
        @click="rolarAte(leitura.ancora)"
      >
        {{ fmt.t(`${NS}.${leitura.id}.VER`) }}
      </button>
    </li>
  </ul>
</template>
