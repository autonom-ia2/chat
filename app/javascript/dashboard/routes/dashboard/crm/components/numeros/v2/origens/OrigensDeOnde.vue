<script setup>
import { computed } from 'vue';
import { useNumerosFormato } from '../useNumerosFormato';
import { larguraDe } from '../barras';

// Números › Origens (#2001, F6) — pergunta 1: "De onde vieram os clientes este mês?". Uma linha por origem (até 5 e
// "Outros caminhos"), com clientes novos, vendas e R$. Sem origem marcada é "Chegou direto", com a frase
// que explica; nunca "desconhecido". Ação única por linha: "Ver" (a lista do funil). Funil sem venda no mês:
// uma frase no resumo, e as linhas sem "nenhuma venda". Em "Todos os funis" não há uma lista só: a linha diz
// para escolher um funil.
const props = defineProps({
  origens: { type: Array, required: true },
  mesNome: { type: String, required: true },
  // "no funil Vendas" / "em todos os funis".
  onde: { type: String, default: '' },
  emTodos: { type: Boolean, default: false },
  moeda: { type: String, default: 'BRL' },
  destinoDe: { type: Function, required: true },
});

const O = 'CRM_NUMEROS_ORIGENS';
const { t, dinheiro } = useNumerosFormato(props.moeda);
const EXPLICADAS = ['direto', 'outras'];

const maior = computed(() =>
  Math.max(1, ...props.origens.map(o => o.clientes))
);
const total = computed(() =>
  props.origens.reduce((acc, o) => acc + o.clientes, 0)
);
const semVenda = computed(() => props.origens.every(o => !o.vendas));

// Sem a permissão de ver valores de venda (#2075) o valor chega null: só a contagem, nunca "R$ 0".
const vendasDe = o => {
  if (semVenda.value) return '';
  if (!o.vendas) return t(`${O}.DE_ONDE.SEM_VENDA`);
  const vendas = t(`${O}.DE_ONDE.VENDAS`, { n: o.vendas }, o.vendas);
  return o.valor === null ? vendas : `${vendas} · ${dinheiro(o.valor)}`;
};

const linhas = computed(() =>
  props.origens.map(o => ({
    ...o,
    nome: t(`${O}.NOMES.${o.tipo.toUpperCase()}`),
    explica: EXPLICADAS.includes(o.tipo)
      ? t(`${O}.EXPLICA.${o.tipo.toUpperCase()}`)
      : '',
    clientesTexto: t(`${O}.DE_ONDE.CLIENTES`, { n: o.clientes }, o.clientes),
    vendasTexto: vendasDe(o),
    largura: larguraDe((o.clientes / maior.value) * 100),
    destino: props.destinoDe(o.tipo),
  }))
);
// O nome do link diz tudo ("Ver os 18 clientes de …"); na tela, só "Ver".
const rotuloDoLink = linha =>
  t(
    `${O}.DE_ONDE.VER_ARIA`,
    {
      n: linha.clientes,
      origem: linha.nome,
      vendas: linha.vendasTexto || t(`${O}.DE_ONDE.SEM_VENDA`),
    },
    linha.clientes
  );
// Destaque do bloco: de onde veio a maior parte (a primeira linha, que não é "Outros caminhos").
const destaque = computed(() => {
  const primeira = linhas.value.find(l => l.tipo !== 'outras');
  return primeira
    ? t(`${O}.DE_ONDE.DESTAQUE`, {
        origem: primeira.nome,
        n: primeira.clientes,
        total: total.value,
      })
    : '';
});
const fraseSemVenda = computed(() =>
  props.emTodos
    ? t(`${O}.DE_ONDE.SEM_VENDA_TODOS`, { mes: props.mesNome })
    : t(`${O}.DE_ONDE.SEM_VENDA_FUNIL`, { mes: props.mesNome })
);
</script>

<template>
  <section
    data-origens-bloco="de-onde"
    aria-labelledby="origens-de-onde"
    class="flex flex-col gap-3"
  >
    <div class="flex flex-col gap-0.5">
      <h2
        id="origens-de-onde"
        class="mb-0 text-base font-semibold text-n-slate-12"
      >
        {{ t(`${O}.DE_ONDE.TITULO`, { mes: mesNome }) }}
      </h2>
      <p class="mb-0 text-sm text-n-slate-11" data-origens-total>
        {{ t(`${O}.DE_ONDE.RESUMO`, { n: total, onde }, total) }}
      </p>
      <p
        v-if="semVenda"
        data-origens-sem-venda
        class="mb-0 text-sm text-n-slate-11"
      >
        {{ fraseSemVenda }}
      </p>
      <p
        v-if="destaque"
        data-origens-destaque
        class="mb-0 mt-2 rounded-lg bg-n-blue-2 px-3 py-2 text-sm font-medium text-n-blue-11"
      >
        {{ destaque }}
      </p>
    </div>
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li v-for="linha in linhas" :key="linha.tipo">
        <component
          :is="linha.destino ? 'RouterLink' : 'div'"
          :to="linha.destino"
          :data-origem="linha.tipo"
          :data-clientes="linha.clientes"
          :data-vendas="linha.vendas"
          :data-valor="linha.valor"
          :data-lista="linha.lista"
          :aria-label="linha.destino ? rotuloDoLink(linha) : undefined"
          class="flex min-h-11 flex-col gap-2 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak"
          :class="
            linha.destino
              ? 'group transition hover:bg-n-alpha-1 hover:ring-n-slate-6 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand motion-reduce:transition-none'
              : ''
          "
        >
          <span
            class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-0.5"
          >
            <span class="text-sm font-semibold text-n-slate-12">
              {{ linha.nome }}
            </span>
            <span class="text-sm tabular-nums text-n-slate-11">
              <strong class="font-semibold text-n-slate-12">
                {{ linha.clientesTexto }}
              </strong>
              <template v-if="linha.vendasTexto">
                {{ t(`${O}.DE_ONDE.SEPARADOR`) }} {{ linha.vendasTexto }}
              </template>
            </span>
          </span>
          <span
            class="block h-2 w-full overflow-hidden rounded-full bg-n-alpha-2"
            aria-hidden="true"
          >
            <span
              class="block h-full rounded-full bg-n-blue-9"
              :class="linha.largura"
            />
          </span>
          <span
            v-if="linha.explica || linha.destino || emTodos"
            class="flex flex-wrap items-start justify-between gap-x-3 gap-y-1"
          >
            <span v-if="linha.explica" class="text-sm text-n-slate-11">
              {{ linha.explica }}
            </span>
            <span
              v-if="linha.destino"
              aria-hidden="true"
              class="ms-auto inline-flex items-center gap-1 text-sm font-medium text-n-blue-11 group-hover:underline"
            >
              {{ t(`${O}.DE_ONDE.VER`) }}
              <span
                class="i-lucide-chevron-right size-4 rtl:rotate-180"
                aria-hidden="true"
              />
            </span>
            <span
              v-else-if="emTodos"
              data-origens-escolha-funil
              class="ms-auto text-sm text-n-slate-11"
            >
              {{ t(`${O}.FUNIL.SEM_LISTA`) }}
            </span>
          </span>
        </component>
      </li>
    </ul>
  </section>
</template>
