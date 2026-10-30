<script setup>
import { computed, ref } from 'vue';
import NumerosRecolhido from './NumerosRecolhido.vue';
import { P, formatarDinheiro } from './numerosTextos';
import { juntarNomes } from './numerosTextosEquipe';
import { larguraDe } from './barras';
import { useNumerosFormato } from './useNumerosFormato';

// "Quem cuidou" (#1992, F5 do #1871), recolhido: o que a IA fez no mês, quem
// está no caminho certo (só com meta, F4; só o positivo), uma linha por pessoa
// em ordem alfabética e a IA no fim, numa linha só, sem meta e sem posição.
const props = defineProps({
  cuidou: { type: Object, required: true },
  moeda: { type: String, default: 'BRL' },
  destinoDe: { type: Function, required: true },
});

const { t, dinheiro, locale } = useNumerosFormato(props.moeda);
const aberta = ref('');

const nomeDaIa = computed(
  () => props.cuidou.ia?.nome || t(`${P}.IA_AJUDOU.IA`)
);

const titulo = computed(() => {
  const n = props.cuidou.pessoas;
  const chave = props.cuidou.ia ? 'TITULO' : 'TITULO_SEM_IA';
  return t(`${P}.CUIDOU.${chave}`, { n }, n);
});

const plataforma = computed(() => {
  const p = props.cuidou.plataforma;
  if (!p) return '';
  // #2075 — sem a chave de valores o servidor manda o R$ vazio (null): a frase fica só com as contagens.
  const chave = p.valor === null ? 'PLATAFORMA_SEM_VALOR' : 'PLATAFORMA';
  return t(
    `${P}.CUIDOU.${chave}`,
    { ...p, ia: nomeDaIa.value, valor: dinheiro(p.valor || 0) },
    p.participou || 0
  );
});

const caminho = computed(() => {
  const nomes = props.cuidou.caminhoCerto.map(n =>
    n.voce ? t(`${P}.CUIDOU.VOCE`) : n.nome
  );
  if (!nomes.length) return '';
  const lista = juntarNomes(nomes, { e: t(`${P}.CUIDOU.E`) });
  return t(`${P}.CUIDOU.CAMINHO`, { nomes: lista });
});

// Uma linha por pessoa (#1999): quem vende e atende tem os dois números lado a
// lado. O prazo por pessoa ainda não é gravado: de quem atende, só quanto
// resolveu, e o link para as conversas dela no relatório.
const detalheDaVenda = v =>
  t(`${P}.CUIDOU.${v.meta ? 'DETALHE_VENDA' : 'DETALHE_VENDA_SEM_META'}`, {
    ...v,
    valor: dinheiro(v.valor),
    meta: dinheiro(v.meta || 0),
  });
const vendaDe = v => ({
  numeros: t(`${P}.CUIDOU.VENDA`, v),
  pct: v.meta ? v.pct : null,
  detalhe: v.valor === null ? '' : detalheDaVenda(v),
});

// Sem meta de casos (#1998), o detalhe repetiria o "resolveu": fica vazio.
const atendeDe = a => ({
  numeros: t(`${P}.CUIDOU.ATENDE_SEM_PRAZO`, a, a.resolveu),
  detalhe: '',
});

const linhaDe = linha => {
  const partes = [
    linha.venda ? vendaDe(linha.venda) : null,
    linha.atende ? atendeDe(linha.atende) : null,
  ].filter(Boolean);
  return {
    chave: `pessoa-${linha.id}`,
    nome: linha.voce
      ? t(`${P}.CUIDOU.VOCE_NOME`, { nome: linha.nome })
      : linha.nome,
    numeros: partes.map(parte => parte.numeros).join(' · '),
    pct: linha.venda ? vendaDe(linha.venda).pct : null,
    detalhe: partes
      .map(parte => parte.detalhe)
      .filter(Boolean)
      .join(' '),
    relatorio: linha.atende
      ? props.destinoDe('relatorio_pessoa', { item: linha })
      : null,
    relatorioTexto: t(`${P}.CUIDOU.VER_CONVERSAS`, { nome: linha.nome }),
  };
};

const linhas = computed(() => props.cuidou.linhas.map(linhaDe));

// O que fechou sem responsável ou com quem saiu da conta (#1999): a última
// linha fecha a conta, e a soma das linhas bate com o topo.
const foraDaEquipe = computed(() => {
  const fora = props.cuidou.foraDaEquipe;
  if (!fora) return '';
  return [
    fora.venda
      ? t(
          `${P}.CUIDOU.${fora.venda.valor === null ? 'FORA_VENDA_SEM_VALOR' : 'FORA_VENDA'}`,
          { fechou: fora.venda.fechou, valor: dinheiro(fora.venda.valor) }
        )
      : null,
    fora.atende
      ? t(`${P}.CUIDOU.ATENDE_SEM_PRAZO`, fora.atende, fora.atende.resolveu)
      : null,
  ]
    .filter(Boolean)
    .join(' · ');
});

const custoDaIa = custo => {
  const emDinheiro = valor =>
    formatarDinheiro(valor, { locale: locale(), moeda: custo.moeda });
  return custo.porConversa === null
    ? t(`${P}.CUIDOU.IA_CUSTO_AGENTES_SEM_CONVERSA`, {
        valor: emDinheiro(custo.valor),
      })
    : t(`${P}.CUIDOU.IA_CUSTO_AGENTES`, {
        valor: emDinheiro(custo.valor),
        porConversa: emDinheiro(custo.porConversa),
      });
};

// A linha da IA não repete a frase do topo (#1999): com a frase, ela diz só o
// que a frase não diz (passou e resolveu sozinha); sem a frase (quem vê um tipo
// de funil só), diz também quantos atendeu e de quantas vendas participou. Um
// número de cada: os mesmos que a frase lê.
const numerosDaIa = i => {
  const comFrase = Boolean(props.cuidou.plataforma);
  const parte = (chave, n, extra = {}) =>
    t(`${P}.CUIDOU.${chave}`, { n, ...extra }, n);
  return [
    comFrase ? null : parte('IA_ATENDEU', i.atendeu),
    !comFrase && i.venda
      ? parte(
          i.venda.valor === null ? 'IA_PARTICIPOU_SEM_VALOR' : 'IA_PARTICIPOU',
          i.venda.participou,
          { valor: dinheiro(i.venda.valor) }
        )
      : null,
    parte('IA_PASSOU', i.passou),
    i.atende ? parte('IA_RESOLVEU_SOZINHA', i.atende.resolveuSozinha) : null,
  ]
    .filter(Boolean)
    .join(' · ');
};

const ia = computed(() => {
  const i = props.cuidou.ia;
  if (!i) return null;
  return {
    nome: nomeDaIa.value,
    numeros: numerosDaIa(i),
    custo: i.custo ? custoDaIa(i.custo) : '',
    destino: props.destinoDe('agente', { item: i }),
    ver: t(`${P}.CUIDOU.${i.agenteId ? 'IA_VER' : 'IA_VER_TODOS'}`),
  };
});

const alternar = chave => {
  aberta.value = aberta.value === chave ? '' : chave;
};
</script>

<template>
  <NumerosRecolhido :titulo="titulo" data-numeros-cuidou>
    <p v-if="plataforma" class="mb-0 text-sm text-n-slate-12">
      {{ plataforma }}
    </p>
    <p
      v-if="caminho"
      data-caminho-certo
      class="mb-0 rounded-xl bg-n-teal-3 px-3 py-2 text-sm text-n-teal-11"
    >
      {{ caminho }}
    </p>

    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="linha in linhas"
        :key="linha.chave"
        class="flex flex-col rounded-xl ring-1 ring-inset ring-n-weak"
      >
        <button
          type="button"
          :aria-expanded="aberta === linha.chave"
          :data-pessoa="linha.chave"
          class="flex min-h-11 w-full flex-col gap-1.5 rounded-xl px-3 py-2 text-start hover:bg-n-alpha-1 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          @click="alternar(linha.chave)"
        >
          <span
            class="flex w-full flex-wrap items-baseline justify-between gap-x-3"
          >
            <span class="text-sm font-semibold text-n-slate-12">
              {{ linha.nome }}
            </span>
            <span class="text-sm text-n-slate-11">{{ linha.numeros }}</span>
          </span>
          <span
            v-if="linha.pct !== null"
            aria-hidden="true"
            class="block h-1 w-full overflow-hidden rounded-full bg-n-alpha-2"
          >
            <span
              class="block h-full rounded-full bg-n-blue-9"
              :class="larguraDe(linha.pct)"
            />
          </span>
        </button>
        <div
          v-if="aberta === linha.chave && (linha.detalhe || linha.relatorio)"
          class="flex flex-wrap items-center justify-between gap-x-3 px-3 pb-2"
        >
          <span v-if="linha.detalhe" class="text-sm text-n-slate-11">
            {{ linha.detalhe }}
          </span>
          <RouterLink
            v-if="linha.relatorio"
            :to="linha.relatorio.to"
            class="inline-flex min-h-11 items-center gap-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            {{ linha.relatorioTexto }}
          </RouterLink>
        </div>
      </li>
      <li
        v-if="foraDaEquipe"
        data-fora-da-equipe
        class="flex min-h-11 flex-wrap items-baseline justify-between gap-x-3 rounded-xl px-3 py-2 ring-1 ring-inset ring-n-weak"
      >
        <span class="text-sm font-semibold text-n-slate-11">
          {{ t(`${P}.CUIDOU.FORA_DA_EQUIPE`) }}
        </span>
        <span class="text-sm text-n-slate-11">{{ foraDaEquipe }}</span>
      </li>
    </ul>

    <div
      v-if="ia"
      data-linha-ia
      class="flex flex-col gap-1 border-t border-n-weak pt-3"
    >
      <div class="flex flex-col gap-1 border-s-2 border-n-iris-9 ps-3">
        <span
          class="flex items-center gap-2 text-sm font-semibold text-n-slate-12"
        >
          {{ ia.nome }}
          <span
            class="rounded-md bg-n-iris-3 px-1.5 text-xs font-semibold text-n-iris-11"
          >
            {{ t(`${P}.CUIDOU.IA_SELO`) }}
          </span>
        </span>
        <span data-ia-numeros class="text-sm text-n-slate-11">
          {{ ia.numeros }}
        </span>
        <span v-if="ia.custo" data-custo-ia class="text-sm text-n-slate-11">
          {{ ia.custo }}
          <span class="text-xs text-n-amber-11">
            {{ t(`${P}.CUIDOU.IA_CUSTO_FALTA`) }}
          </span>
        </span>
        <span v-if="ia.destino" data-ia-semana class="text-xs text-n-slate-11">
          {{ t(`${P}.CUIDOU.IA_SEMANA`) }}
        </span>
        <RouterLink
          v-if="ia.destino"
          :to="ia.destino.to"
          class="inline-flex min-h-11 w-fit items-center gap-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
        >
          {{ ia.ver }}
          <span
            class="i-lucide-arrow-right size-3.5 rtl:rotate-180"
            aria-hidden="true"
          />
        </RouterLink>
      </div>
    </div>
    <p class="mb-0 text-xs text-n-slate-11">{{ t(`${P}.CUIDOU.RODAPE`) }}</p>
  </NumerosRecolhido>
</template>
