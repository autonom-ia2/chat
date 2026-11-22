<script setup>
// #3098 — quem recebeu a campanha e comprou em até N dias depois do envio (a janela escolhida na campanha), separado
// entre quem respondeu e quem comprou sem responder, e, com grupo de controle, a comparação com quem ficou sem
// receber. Fica abaixo da faixa do CRM, que conta só quem respondeu: por isso o nome é "quem recebeu e comprou" e o
// valor é "em compras", para não parecer um segundo total de vendas. Sem valor de venda (`valor` nulo), só contagens.
//
// `vendas`: { janela_dias, contando_ate (epoch ou nulo), receberam, compraram, responderam, sem_responder, controle }
//   compraram/responderam/sem_responder: { pessoas, valor: [{ currency, cents }] | null }
//   controle: nulo ou { pessoas, compraram }
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { wonValueText } from './resultMetrics';
import { compararComControle, emGente } from './comparacaoComControle';

const props = defineProps({
  vendas: { type: Object, required: true },
});

const NS = 'CAMPANHA_VENDAS.RESULTADO';
const { t, locale } = useI18n();
const idioma = computed(() => locale.value.replace('_', '-'));
const inteiro = numero => new Intl.NumberFormat(idioma.value).format(numero);

const veValores = computed(() => Array.isArray(props.vendas.compraram?.valor));
const dinheiro = valor => wonValueText(valor, idioma.value);
const quantas = computed(() => props.vendas.compraram?.pessoas ?? 0);
const contando = computed(() => Boolean(props.vendas.contando_ate));

const situacao = computed(() => {
  const { contando_ate: ate, janela_dias: dias } = props.vendas;
  if (!ate) return t(`${NS}.FECHADO`, { dias });
  const data = new Intl.DateTimeFormat(idioma.value, {
    day: 'numeric',
    month: 'long',
  }).format(new Date(ate * 1000));
  return t(`${NS}.CONTANDO_ATE`, { data });
});

const partes = computed(() =>
  [
    ['responderam', 'RESPONDERAM'],
    ['sem_responder', 'SEM_RESPONDER'],
  ].map(([chave, rotulo]) => ({
    chave,
    rotulo: t(`${NS}.${rotulo}`),
    pessoas: props.vendas[chave]?.pessoas ?? 0,
    valor: props.vendas[chave]?.valor,
  }))
);

const receberam = computed(() => ({
  pessoas: props.vendas.receberam ?? 0,
  compraram: quantas.value,
}));
const controle = computed(() => props.vendas.controle);
const comparacao = computed(() =>
  controle.value ? compararComControle(receberam.value, controle.value) : null
);
// Com a contagem encerrada, a frase de "ainda não dá" vira "não deu": não vai chegar resultado novo.
const SEM_RESPOSTA = ['POUCOS', 'POUCAS_COMPRAS'];
const fraseDaComparacao = computed(() => {
  const { chave, vezes } = comparacao.value;
  const fechada = !contando.value && SEM_RESPOSTA.includes(chave);
  return t(`${NS}.${chave}${fechada ? '_FECHADO' : ''}`, { vezes });
});
// "De cada 100 que receberam, 5 compraram." — a taxa de cada lado em gente, com os mesmos números da frase acima.
const lados = computed(() => {
  if (!controle.value) return [];
  const gente = emGente(receberam.value, controle.value);
  const frase = (n, sufixo) =>
    t(
      `${NS}.DE_CADA${sufixo}`,
      { escala: inteiro(gente.escala), n: inteiro(n) },
      n
    );
  return [
    {
      chave: 'receberam',
      lado: receberam.value,
      n: gente.receberam,
      sufixo: '',
    },
    {
      chave: 'sem_receber',
      lado: controle.value,
      n: gente.controle,
      sufixo: '_SEM',
    },
  ].map(({ chave, lado, n, sufixo }) => ({
    chave,
    frase: frase(n, sufixo),
    apoio: t(`${NS}.DE`, {
      compraram: inteiro(lado.compraram),
      total: inteiro(lado.pessoas),
    }),
  }));
});
</script>

<template>
  <section
    class="flex flex-col gap-5 p-5 border rounded-2xl border-n-weak bg-n-solid-1"
    data-vendas-da-campanha
  >
    <div class="flex flex-col gap-1">
      <h2 class="m-0 text-base font-semibold text-n-slate-12">
        {{ t(`${NS}.TITULO`) }}
      </h2>
      <p class="m-0 text-sm text-n-slate-11" data-situacao>{{ situacao }}</p>
    </div>

    <p
      v-if="quantas === 0"
      class="m-0 text-lg font-medium text-n-slate-12"
      data-ninguem
    >
      {{
        contando
          ? t(`${NS}.NINGUEM`)
          : t(`${NS}.NINGUEM_FECHADO`, { dias: vendas.janela_dias })
      }}
    </p>
    <template v-else>
      <div class="flex flex-col gap-1" data-total>
        <p
          v-if="veValores"
          class="m-0 text-3xl font-semibold tabular-nums text-n-slate-12"
          data-valor
        >
          {{ t(`${NS}.VALOR`, { valor: dinheiro(vendas.compraram.valor) }) }}
        </p>
        <p
          class="m-0 tabular-nums"
          :class="
            veValores
              ? 'text-base text-n-slate-11'
              : 'text-2xl font-semibold text-n-slate-12'
          "
          data-compraram
        >
          {{ t(`${NS}.COMPRARAM`, { n: inteiro(quantas) }, quantas) }}
        </p>
      </div>

      <ul class="grid gap-3 p-0 m-0 list-none sm:grid-cols-2">
        <li
          v-for="parte in partes"
          :key="parte.chave"
          class="flex flex-col gap-1 px-4 py-3 rounded-xl bg-n-alpha-1"
          :data-parte="parte.chave"
        >
          <span class="text-sm text-n-slate-11">{{ parte.rotulo }}</span>
          <span class="text-lg font-semibold tabular-nums text-n-slate-12">
            {{
              t(`${NS}.PESSOAS`, { n: inteiro(parte.pessoas) }, parte.pessoas)
            }}
          </span>
          <span
            v-if="veValores && parte.pessoas > 0"
            class="text-sm tabular-nums text-n-slate-11"
          >
            {{ dinheiro(parte.valor) }}
          </span>
        </li>
      </ul>
    </template>

    <div
      v-if="comparacao"
      class="flex flex-col gap-4 pt-5 border-t border-n-weak"
      data-comparacao
    >
      <h3 class="m-0 text-sm font-semibold text-n-slate-12">
        {{ t(`${NS}.COMPARAR_TITULO`) }}
      </h3>
      <p
        class="m-0 text-lg font-semibold text-n-slate-12"
        :data-frase="comparacao.chave"
      >
        {{ fraseDaComparacao }}
      </p>
      <ul
        v-if="quantas > 0 || controle.compraram > 0"
        class="flex flex-col gap-3 p-0 m-0 list-none"
      >
        <li
          v-for="item in lados"
          :key="item.chave"
          class="flex flex-col gap-0.5"
          :data-lado="item.chave"
        >
          <span class="text-base text-n-slate-12">{{ item.frase }}</span>
          <span class="text-sm tabular-nums text-n-slate-11">
            {{ item.apoio }}
          </span>
        </li>
      </ul>
    </div>

    <p v-if="!veValores" class="m-0 text-xs text-n-slate-11" data-so-contagem>
      {{ t(`${NS}.SO_CONTAGEM`) }}
    </p>
  </section>
</template>
