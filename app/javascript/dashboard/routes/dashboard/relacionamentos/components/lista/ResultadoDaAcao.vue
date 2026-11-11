<script setup>
import { useI18n } from 'vue-i18n';

// #2894 — o que uma ação em grupo (criar cards, etiquetar, apagar) diz dentro
// do diálogo. É a região viva permanente: já está na tela, vazia, antes de a
// ação começar. Enquanto roda: "50 de 120". Depois: a frase do que foi feito,
// quem ficou de fora com o motivo em palavras e, se parou no meio, quantas
// ainda não foram.
defineProps({
  // { feitas, total } enquanto a ação roda.
  andamento: { type: Object, default: null },
  // { feitas, deFora: [{ id, nome, motivo }], faltam, erro } depois dela.
  resultado: { type: Object, default: null },
  // A frase do que foi feito, de quem usa: recebe quantas deram certo.
  frase: { type: Function, required: true },
});

const { t } = useI18n();
const ACAO = 'RELACIONAMENTOS.LISTA.ACAO';

const motivoEmPalavras = motivo => t(`${ACAO}.MOTIVO_${motivo.toUpperCase()}`);
</script>

<template>
  <div role="status" class="flex flex-col gap-3">
    <p
      v-if="andamento"
      data-relacionamentos="andamento"
      class="pb-3 m-0 text-sm tabular-nums text-n-slate-11"
    >
      {{ t(`${ACAO}.ANDAMENTO`, andamento) }}
    </p>
    <template v-else-if="resultado">
      <p class="m-0 text-base font-medium text-n-slate-12">
        {{ frase(resultado.feitas) }}
      </p>
      <template v-if="resultado.deFora.length">
        <p class="m-0 text-sm text-n-slate-11">
          {{ t(`${ACAO}.FICARAM_DE_FORA`) }}
        </p>
        <ul
          class="flex flex-col gap-1 p-0 m-0 overflow-y-auto text-sm list-none max-h-60 text-n-slate-12"
        >
          <li v-for="item in resultado.deFora" :key="item.id">
            {{ item.nome || t(`${ACAO}.SEM_NOME`) }} ·
            {{ motivoEmPalavras(item.motivo) }}
          </li>
        </ul>
      </template>
      <p
        v-if="resultado.erro"
        data-relacionamentos="ainda-nao"
        class="m-0 text-sm text-n-ruby-11"
      >
        {{ t(`${ACAO}.AINDA_NAO`, { count: resultado.faltam.length }) }}
      </p>
    </template>
  </div>
</template>
