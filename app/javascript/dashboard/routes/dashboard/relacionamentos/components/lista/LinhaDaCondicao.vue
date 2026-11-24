<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import ValorDaCondicao from './ValorDaCondicao.vue';
import {
  comComo,
  comInformacao,
  comosDa,
  pedeValor,
  rotuloDoComo,
  temUmComoSo,
} from '../../lista/informacoes';

// #3168 — uma linha de "Por outra informação", empilhada (a gaveta tem 26 rem):
// Informação (da pessoa ou dos campos da conta), Como (depende do tipo), o
// valor (some quando o "como" não pede) e a lixeira "Tirar esta informação".
// Não muda nada: a linha nova sobe por `mudar`. Quando o tipo tem um "como" só
// (Bloqueada, Não tem a etiqueta), a linha não pergunta "Como": vai direto ao
// valor (#3168, diretor de arte).
const props = defineProps({
  condicao: { type: Object, required: true },
  // { daPessoa: [...], daConta: [...] } (lista/informacoes.js).
  informacoes: { type: Object, required: true },
  numero: { type: Number, required: true },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['mudar', 'tirar']);

const { t } = useI18n();
const id = useId();
const CC = 'RELACIONAMENTOS.LISTA.CONDICOES';

const paraEscolha = item => ({ value: item.chave, label: item.rotulo });
const grupos = computed(() =>
  [
    { label: t(`${CC}.DA_PESSOA`), itens: props.informacoes.daPessoa },
    { label: t(`${CC}.DA_CONTA`), itens: props.informacoes.daConta },
  ]
    .filter(({ itens }) => itens.length)
    .map(({ label, itens }) => ({ label, options: itens.map(paraEscolha) }))
);
const todas = computed(() => [
  ...props.informacoes.daPessoa,
  ...props.informacoes.daConta,
]);
const informacao = computed(
  () => todas.value.find(item => item.chave === props.condicao.chave) ?? null
);
const opcoesDoComo = computed(() =>
  comosDa(props.condicao).map(como => ({
    value: como,
    label: t(`${CC}.COMO.${rotuloDoComo(props.condicao.tipo, como)}`),
  }))
);

const escolherInformacao = chave => {
  const escolhida = todas.value.find(item => item.chave === chave);
  if (escolhida) emit('mudar', comInformacao(props.condicao, escolhida));
};
const escolherComo = como => emit('mudar', comComo(props.condicao, como));
const mudarValor = valor => emit('mudar', { ...props.condicao, valor });
</script>

<template>
  <div
    class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1 ring-1 ring-inset ring-n-weak"
    data-relacionamentos="linha-da-condicao"
    :data-condicao="condicao.id"
  >
    <div class="flex items-end min-w-0 gap-2">
      <div class="flex flex-col flex-1 min-w-0">
        <label
          :for="`${id}-informacao`"
          class="mb-1.5 text-heading-3 text-n-slate-12"
        >
          {{ t(`${CC}.INFORMACAO`) }}
        </label>
        <ChoiceSelect
          :model-value="condicao.chave"
          :groups="grupos"
          :trigger-id="`${id}-informacao`"
          :aria-label="t(`${CC}.INFORMACAO_N`, { numero })"
          :placeholder="t(`${CC}.ESCOLHA_UMA_INFORMACAO`)"
          wrap-selected
          class="w-full"
          data-relacionamentos="informacao-da-condicao"
          @update:model-value="escolherInformacao"
        />
      </div>
      <Button
        ghost
        slate
        type="button"
        class="size-11 shrink-0"
        icon="i-lucide-trash-2"
        data-relacionamentos="tirar-condicao"
        :aria-label="t(`${CC}.TIRAR_N`, { numero })"
        :title="t(`${CC}.TIRAR`)"
        @click="emit('tirar')"
      />
    </div>
    <template v-if="condicao.chave">
      <div v-if="!temUmComoSo(condicao)" class="flex flex-col min-w-0">
        <label
          :for="`${id}-como`"
          class="mb-1.5 text-heading-3 text-n-slate-12"
        >
          {{ t(`${CC}.COMO_ROTULO`) }}
        </label>
        <ChoiceSelect
          :model-value="condicao.como"
          :options="opcoesDoComo"
          :trigger-id="`${id}-como`"
          :aria-label="t(`${CC}.COMO_ROTULO`)"
          wrap-selected
          class="w-full"
          data-relacionamentos="como-da-condicao"
          @update:model-value="escolherComo"
        />
      </div>
      <ValorDaCondicao
        v-if="pedeValor(condicao.como)"
        :condicao="condicao"
        :opcoes="informacao?.opcoes ?? []"
        :erro="erro"
        @mudar="mudarValor"
      />
    </template>
  </div>
</template>
