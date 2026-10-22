<script setup>
import { computed } from 'vue';
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// Bloco "Vendendo" ou "Atendendo" (#1871): três números, cada um abre a lista
// que já existe. Venda e atendimento nunca se misturam no mesmo bloco.
const props = defineProps({
  tipo: { type: String, required: true }, // 'vendendo' | 'atendendo'
  bloco: { type: Object, required: true },
  moeda: { type: String, default: 'BRL' },
  destinoDe: { type: Function, required: true },
});

const { t, dinheiro } = useNumerosFormato(props.moeda);

// Na visão "Equipe" (#1992) o título diz que o bloco é de todos.
const titulo = computed(() => {
  const base = props.tipo === 'vendendo' ? 'VENDENDO' : 'ATENDENDO';
  const equipe = props.bloco.escopo === 'equipe' ? '_EQUIPE' : '';
  return t(`${P}.BLOCO.${base}${equipe}`);
});

const ROTULOS = {
  andamento: 'ANDAMENTO',
  atrasados: 'ATRASADOS',
  resolvidos: 'RESOLVIDOS',
  com_voce: 'COM_VOCE',
  deu_certo: 'DEU_CERTO',
  lembretes: 'LEMBRETES',
  parados_atende: 'PARADOS_ATENDE',
};

const numero = item => {
  // #2075 — sem a chave de valores o R$ vem vazio (null): o número grande vira a contagem.
  if (item.tipo === 'fechadas' && item.valor === null)
    return {
      grande: String(item.n),
      rotulo: t(`${P}.BLOCO.FECHADAS_SEM_VALOR`, { n: item.n }, item.n),
    };
  if (item.tipo === 'fechadas')
    return {
      grande: dinheiro(item.valor),
      rotulo: t(`${P}.BLOCO.FECHADAS`, { n: item.n }, item.n),
    };
  return {
    grande: String(item.n),
    rotulo: t(`${P}.BLOCO.${ROTULOS[item.tipo]}`, { n: item.n }, item.n),
  };
};

const itens = computed(() =>
  props.bloco.itens.map(item => ({
    ...item,
    ...numero(item),
    destino: props.destinoDe(item.tipo, { item }),
  }))
);
</script>

<template>
  <section :data-numeros-bloco="tipo" class="flex flex-col gap-2">
    <h3 class="mb-0 text-sm font-semibold text-n-slate-11">{{ titulo }}</h3>
    <ul class="m-0 grid list-none grid-cols-1 gap-2 p-0 sm:grid-cols-3">
      <li v-for="item in itens" :key="item.tipo" class="min-w-0">
        <component
          :is="item.destino ? 'RouterLink' : 'div'"
          :to="item.destino?.to"
          :data-numero="item.tipo"
          class="flex h-full min-h-11 items-center justify-between gap-3 rounded-xl bg-n-solid-1 px-4 py-3 ring-1 ring-inset ring-n-weak sm:flex-col sm:items-start sm:justify-start sm:gap-1"
          :class="
            item.destino
              ? 'transition hover:bg-n-alpha-1 hover:ring-n-slate-6 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand'
              : ''
          "
        >
          <span
            class="flex min-w-0 items-baseline gap-2 sm:flex-col sm:gap-0.5"
          >
            <strong
              class="text-xl font-semibold tabular-nums text-n-slate-12 sm:text-2xl"
            >
              {{ item.grande }}
            </strong>
            <span class="text-sm text-n-slate-11">{{ item.rotulo }}</span>
          </span>
          <span
            v-if="item.destino"
            class="i-lucide-chevron-right size-4 shrink-0 text-n-slate-10 sm:hidden rtl:rotate-180"
            aria-hidden="true"
          />
        </component>
      </li>
    </ul>
  </section>
</template>
