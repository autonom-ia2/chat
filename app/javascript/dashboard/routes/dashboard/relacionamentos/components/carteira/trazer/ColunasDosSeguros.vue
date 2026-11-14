<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { SITUACAO_DA_COLUNA } from '../../../carteira/segurosDaPlanilha';

// #2897 — onde está cada coisa do seguro na planilha: uma linha por coisa (o
// número da apólice, a seguradora, o tipo, quando termina…) e, ao lado, a
// coluna da planilha em que ela está. A tela chega com o que o servidor
// sugeriu; a pessoa só troca o que estiver errado e aponta o que faltou. Nada
// é gravado aqui: a escolha sobe (`apontar`) e quem confirma tudo de uma vez é
// o botão do Conferir.
const props = defineProps({
  // `[{ destino, chave, obrigatorio, situacao, coluna }]`
  // (carteira/segurosDaPlanilha.js, `colunasDosSeguros`).
  linhas: { type: Array, required: true },
  // As colunas da planilha que servem a um seguro: `[{ indice, nome }]`.
  colunas: { type: Array, required: true },
  ocupado: { type: Boolean, default: false },
  // Os destinos que o Conferir acabou de dizer que faltam, e o id do alerta.
  faltam: { type: Array, default: () => [] },
  idDoAlerta: { type: String, default: undefined },
});
const emit = defineEmits(['apontar']);

const { t } = useI18n();
const id = useId();
const BASE = 'RELACIONAMENTOS_CARTEIRA.TRAZER.COLUNAS';
const SEM_COLUNA = '';

const { CONFIRMADA, ESCOLHIDA, SUGERIDA, FALTA } = SITUACAO_DA_COLUNA;
// O que a linha diz embaixo do nome, e com que cor. A coluna que não é
// obrigatória e não foi achada só diz que pode ficar sem.
const AVISOS = {
  [CONFIRMADA]: { chave: 'CERTA', classe: 'text-n-teal-11' },
  [ESCOLHIDA]: { chave: 'ESCOLHIDA', classe: 'text-n-slate-11' },
  [SUGERIDA]: { chave: 'SUGERIDA', classe: 'text-n-slate-11' },
  [FALTA]: { chave: 'FALTA', classe: 'text-n-ruby-11' },
};
const SEM_AVISO = { chave: 'OPCIONAL', classe: 'text-n-slate-11' };

const opcoes = computed(() =>
  props.colunas.map(({ indice, nome }) => ({
    value: indice,
    label: nome || t(`${BASE}.COLUNA_SEM_NOME`, { numero: indice + 1 }),
  }))
);

const itens = computed(() =>
  props.linhas.map(linha => {
    const aviso = AVISOS[linha.situacao] ?? SEM_AVISO;
    return {
      ...linha,
      nome: t(linha.chave),
      aviso: t(`${BASE}.SITUACAO.${aviso.chave}`),
      classeDoAviso: aviso.classe,
      faltando: props.faltam.includes(linha.destino),
    };
  })
);
</script>

<template>
  <ul
    data-carteira="colunas-dos-seguros"
    :aria-label="t(`${BASE}.LISTA`)"
    class="flex flex-col p-0 m-0 list-none border divide-y rounded-2xl border-n-weak divide-n-weak bg-n-solid-1"
  >
    <li
      v-for="item in itens"
      :key="item.destino"
      :data-destino="item.destino"
      :data-situacao="item.situacao"
      class="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:gap-6"
    >
      <div class="flex flex-col min-w-0 gap-0.5">
        <label
          :for="`${id}-${item.destino}`"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ item.nome }}
        </label>
        <p
          :id="`${id}-${item.destino}-aviso`"
          data-carteira="situacao-da-coluna"
          class="m-0 text-sm"
          :class="item.classeDoAviso"
        >
          {{ item.aviso }}
        </p>
      </div>
      <div class="w-full sm:w-64 shrink-0">
        <ChoiceSelect
          class="w-full"
          :model-value="item.coluna ?? SEM_COLUNA"
          :options="opcoes"
          :trigger-id="`${id}-${item.destino}`"
          :aria-label="t(`${BASE}.ESCOLHER`, { destino: item.nome })"
          :placeholder="t(`${BASE}.ESCOLHA`)"
          :described-by="
            item.faltando && idDoAlerta
              ? idDoAlerta
              : `${id}-${item.destino}-aviso`
          "
          :invalid="item.faltando"
          :disabled="ocupado"
          wrap-selected
          @update:model-value="coluna => emit('apontar', item.destino, coluna)"
        />
      </div>
    </li>
  </ul>
</template>
