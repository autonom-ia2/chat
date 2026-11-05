<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2499 — o gatilho no "Alterar": o seletor, agrupado quando há mais de um
// grupo (conversa e mensagem, card do funil), e o que o gatilho escolhido pede
// pelo catálogo (`parametros`): a etapa, agrupada pelo funil, ou o funil
// (vazio = todos). Os de card só chegam aqui com a flag e para quem pode mexer
// no funil.
const props = defineProps({
  modelValue: { type: Object, default: null },
  gatilhos: { type: Array, required: true },
  // { funis: [{ value, label }], etapas: [{ label, options }] }
  escolhas: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const idTipo = useId();

const opcao = item => ({ value: item.tipo, label: t(item.frase) });
const grupos = computed(() => {
  const nomes = [...new Set(props.gatilhos.map(item => item.grupo))];
  if (nomes.length < 2) return null;
  return nomes.map(grupo => ({
    label: t(
      `AUTOMACAO_LIVRE.GRUPOS_DO_GATILHO.${(grupo || '').toUpperCase()}`
    ),
    options: props.gatilhos.filter(item => item.grupo === grupo).map(opcao),
  }));
});
const opcoes = computed(() => props.gatilhos.map(opcao));

const entrada = computed(() =>
  props.gatilhos.find(item => item.tipo === props.modelValue?.tipo)
);
const parametros = computed(() => entrada.value?.parametros || []);
const deEtapa = computed(() =>
  parametros.value.some(parametro => parametro.peca === 'etapa')
);

const funis = computed(() => [
  { value: '', label: t('AUTOMACAO_LIVRE.GATILHO_DO_CARD.TODOS_OS_FUNIS') },
  ...(props.escolhas.funis || []),
]);

// Trocar o tipo apaga o que o anterior pedia (etapa, funil), mas mantém os
// filtros: o painel mostra o que entra e o que sai deles.
const trocarTipo = tipo => {
  const { filtros } = props.modelValue || {};
  emit('update:modelValue', filtros ? { tipo, filtros } : { tipo });
};
// Sem escolha (o funil vazio), a chave não vai na receita.
const mudar = (nome, valor) => {
  const { [nome]: _antes, ...resto } = props.modelValue || {};
  emit(
    'update:modelValue',
    valor === '' || valor === null ? resto : { ...resto, [nome]: valor }
  );
};
</script>

<template>
  <div class="flex flex-col gap-4" data-peca="gatilho">
    <div class="flex flex-col gap-1.5">
      <label :for="idTipo" class="text-sm font-medium text-n-slate-12">
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO') }}
      </label>
      <ChoiceSelect
        :model-value="modelValue?.tipo || ''"
        :trigger-id="idTipo"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.TIPO_GATILHO')"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="opcoes"
        :groups="grupos || []"
        @update:model-value="trocarTipo"
      />
    </div>

    <div
      v-for="parametro in parametros"
      :key="parametro.nome"
      class="flex flex-col gap-1.5"
      :data-parametro="parametro.nome"
    >
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(parametro.frase) }}
      </span>
      <ChoiceSelect
        v-if="parametro.peca === 'etapa'"
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :groups="escolhas.etapas || []"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
      <ChoiceSelect
        v-else
        :model-value="modelValue?.[parametro.nome] ?? ''"
        :aria-label="$t(parametro.frase)"
        :options="funis"
        @update:model-value="valor => mudar(parametro.nome, valor)"
      />
    </div>

    <p
      v-if="deEtapa"
      data-nao-dispara
      class="px-4 py-3 mb-0 text-sm rounded-xl bg-n-amber-3 text-n-amber-12"
    >
      {{ $t('AUTOMACAO_LIVRE.GATILHO_NAO_DISPARA') }}
    </p>
  </div>
</template>
