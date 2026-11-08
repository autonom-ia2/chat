<script setup>
import { computed, ref } from 'vue';
import CartaoDoPainel from '../comum/CartaoDoPainel.vue';
import LinkDaConversa from '../comum/LinkDaConversa.vue';
import TabelaDoPainel from './TabelaDoPainel.vue';
import { useFormatoDoPainel } from '../../../composables/useFormatoDoPainel';
import { ordenar } from '../../../utils/desempenhoDetalhe';
import { nomeCurtoDoAgente } from '../../../utils/desempenhoContrato';

// #2226 v2 — as regras da instrução que o agente mais quebrou, com a descrição embaixo do nome e as
// conversas que provam cada uma (abrem numa linha embaixo).
const props = defineProps({
  painel: { type: Object, required: true },
});

const { t } = useFormatoDoPainel();
const B = 'AGENTS.DESEMPENHO2.B.REGRAS';
const ordem = ref({ coluna: 'procuras', sentido: 'desc' });
const abertas = ref([]);
const nomeDaIa = computed(() =>
  nomeCurtoDoAgente(
    props.painel.meta?.agente?.nome,
    t('AGENTS.DESEMPENHO2.A.COMUM.AGENTE')
  )
);

const linhas = computed(() =>
  ordenar(
    (props.painel.qualidade?.regras || []).map(regra => ({
      ...regra,
      chave: regra.id,
      quase_sempre: regra.sistemica ? 1 : 0,
      exemplos: regra.exemplos || [],
    })),
    ordem.value
  )
);

const colunas = computed(() => [
  { id: 'nome', titulo: t(`${B}.COL.REGRA`), ordenavel: true },
  {
    id: 'procuras',
    titulo: t(`${B}.COL.PROCURAS`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'numero',
  },
  {
    id: 'pct',
    titulo: t(`${B}.COL.PCT`),
    alinhar: 'fim',
    ordenavel: true,
    formato: 'pct',
  },
  { id: 'quase_sempre', titulo: t(`${B}.COL.QUASE_SEMPRE`), ordenavel: true },
  { id: 'exemplos', titulo: t(`${B}.COL.EXEMPLOS`) },
]);

const alternar = chave => {
  abertas.value = abertas.value.includes(chave)
    ? abertas.value.filter(item => item !== chave)
    : [...abertas.value, chave];
};
</script>

<template>
  <CartaoDoPainel
    :titulo="t(`${B}.TITULO`)"
    :descricao="t(`${B}.DESCRICAO`, { nome: nomeDaIa })"
    :unidade="t(`${B}.UNIDADE`)"
  >
    <TabelaDoPainel
      :colunas="colunas"
      :linhas="linhas"
      :ordem="ordem"
      :abertas="abertas"
      :legenda="t(`${B}.TITULO`)"
      :vazio="t(`${B}.VAZIO`)"
      largura-minima="min-w-[44rem]"
      @ordenar="ordem = $event"
    >
      <template #celula-nome="{ linha }">
        <span class="flex flex-col gap-0.5 min-w-[16rem]">
          <span class="font-semibold">{{
            linha.nome || t('AGENTS.DESEMPENHO2.B.SEM_NOME')
          }}</span>
          <span v-if="linha.descricao" class="text-xs text-n-slate-11">{{
            linha.descricao
          }}</span>
        </span>
      </template>
      <template #celula-quase_sempre="{ linha }">
        <span
          v-if="linha.sistemica"
          class="inline-flex px-2 py-0.5 rounded-full text-xs font-semibold bg-n-amber-3 text-n-amber-11 whitespace-nowrap"
        >
          {{ t(`${B}.SIM`) }}
        </span>
      </template>
      <template #celula-exemplos="{ linha }">
        <button
          v-if="linha.exemplos.length"
          type="button"
          class="inline-flex items-center gap-1 min-h-11 -my-2.5 text-sm text-n-blue-11 hover:underline whitespace-nowrap"
          :aria-expanded="abertas.includes(linha.chave)"
          :data-exemplos="linha.chave"
          @click="alternar(linha.chave)"
        >
          <span
            class="size-4"
            :class="
              abertas.includes(linha.chave)
                ? 'i-lucide-chevron-up'
                : 'i-lucide-chevron-down'
            "
            aria-hidden="true"
          />
          {{
            abertas.includes(linha.chave)
              ? t(`${B}.ESCONDER_EXEMPLOS`)
              : t(`${B}.VER_EXEMPLOS`, { n: linha.exemplos.length })
          }}
        </button>
      </template>
      <template #expansao="{ linha }">
        <ul class="grid gap-2 m-0 p-0 list-none md:grid-cols-2">
          <li
            v-for="prova in linha.exemplos"
            :key="`${prova.conversa}-${prova.procura}`"
            class="rounded-xl bg-n-solid-1 ring-1 ring-n-weak px-3 py-2"
          >
            <LinkDaConversa :prova="prova" com-resumo />
          </li>
        </ul>
      </template>
    </TabelaDoPainel>
  </CartaoDoPainel>
</template>
