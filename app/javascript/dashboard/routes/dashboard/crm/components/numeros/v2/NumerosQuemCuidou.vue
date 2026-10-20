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
  return t(
    `${P}.CUIDOU.PLATAFORMA`,
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

const linhaDeVenda = (linha, nome) => {
  const v = linha.venda;
  const params = {
    ...v,
    valor: dinheiro(v.valor),
    meta: dinheiro(v.meta || 0),
  };
  return {
    chave: `venda-${linha.id}`,
    nome,
    numeros: t(`${P}.CUIDOU.VENDA`, v),
    pct: v.meta ? v.pct : null,
    detalhe: v.meta
      ? t(`${P}.CUIDOU.DETALHE_VENDA`, params)
      : t(`${P}.CUIDOU.DETALHE_VENDA_SEM_META`, params),
    relatorio: null,
  };
};

// O prazo por pessoa ainda não é gravado: a linha de quem atende diz só quanto
// resolveu, e abre as conversas dela no relatório (quando a pessoa pode abrir).
const linhaDeAtendimento = (linha, nome) => {
  const a = linha.atende;
  return {
    chave: `atende-${linha.id}`,
    nome,
    numeros: t(`${P}.CUIDOU.ATENDE_SEM_PRAZO`, a, a.resolveu),
    pct: a.meta ? a.pct : null,
    detalhe: t(`${P}.CUIDOU.DETALHE_ATENDE_SEM_META`, a, a.resolveu),
    relatorio: props.destinoDe('relatorio_pessoa', { item: linha }),
    relatorioTexto: t(`${P}.CUIDOU.VER_CONVERSAS`, { nome: linha.nome }),
  };
};

const linhas = computed(() =>
  props.cuidou.linhas.map(linha => {
    const nome = linha.voce
      ? t(`${P}.CUIDOU.VOCE_NOME`, { nome: linha.nome })
      : linha.nome;
    return linha.venda
      ? linhaDeVenda(linha, nome)
      : linhaDeAtendimento(linha, nome);
  })
);

const custoDaIa = custo => {
  const emDinheiro = valor =>
    formatarDinheiro(valor, { locale: locale(), moeda: custo.moeda });
  return custo.porConversa === null
    ? t(`${P}.CUIDOU.IA_CUSTO_SEM_CONVERSA`, { valor: emDinheiro(custo.valor) })
    : t(`${P}.CUIDOU.IA_CUSTO`, {
        valor: emDinheiro(custo.valor),
        porConversa: emDinheiro(custo.porConversa),
      });
};

const ia = computed(() => {
  const i = props.cuidou.ia;
  if (!i) return null;
  const partes = [];
  if (i.venda)
    partes.push(
      t(
        `${P}.CUIDOU.IA_VENDA`,
        { ...i.venda, valor: dinheiro(i.venda.valor) },
        i.venda.participou
      )
    );
  if (i.atende)
    partes.push(
      t(`${P}.CUIDOU.IA_ATENDE`, {
        resolveu: i.atende.resolveuSozinha,
        passou: i.atende.passou,
      })
    );
  return {
    nome: nomeDaIa.value,
    partes,
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
          v-if="aberta === linha.chave"
          class="flex flex-wrap items-center justify-between gap-x-3 px-3 pb-2"
        >
          <span class="text-sm text-n-slate-11">{{ linha.detalhe }}</span>
          <RouterLink
            v-if="linha.relatorio"
            :to="linha.relatorio.to"
            class="inline-flex min-h-11 items-center gap-1 text-sm font-semibold text-n-blue-11 hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          >
            {{ linha.relatorioTexto }}
          </RouterLink>
        </div>
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
        <span
          v-for="parte in ia.partes"
          :key="parte"
          class="text-sm text-n-slate-11"
        >
          {{ parte }}
        </span>
        <span v-if="ia.custo" data-custo-ia class="text-sm text-n-slate-11">
          {{ ia.custo }}
          <span class="text-xs text-n-amber-11">
            {{ t(`${P}.CUIDOU.IA_CUSTO_FALTA`) }}
          </span>
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
