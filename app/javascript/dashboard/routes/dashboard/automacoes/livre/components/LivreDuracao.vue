<script setup>
import { computed, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { contagemDaDuracao } from '../frases';

// #2414 F5 — quanto tempo: um número e a unidade (minutos, horas ou dias; no
// "daqui" do retorno, também meses, G69).
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  unidades: { type: Array, required: true },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
const id = useId();

const opcoes = computed(() =>
  props.unidades.map(item => ({
    value: item.valor,
    label: t(item.frase, {}, contagemDaDuracao(props.modelValue?.valor)),
  }))
);

// O esquema pede inteiro de 1 a 3650; em meses (G69), de 1 a 120. Apagado,
// fica vazio (o "Salvar" espera um número) em vez de voltar sozinho para 1.
const MAXIMO = 3650;
const TETOS = { meses: 120 };
const tetoDa = unidade => TETOS[unidade] || MAXIMO;
const maximo = computed(() => tetoDa(props.modelValue?.unidade));
const lerNumero = texto =>
  texto === ''
    ? null
    : Math.min(Math.max(Math.trunc(Number(texto)) || 1, 1), maximo.value);

const mudar = (chave, novo) =>
  emit('update:modelValue', { ...(props.modelValue || {}), [chave]: novo });

// Trocar a unidade traz o número para dentro do teto dela.
const mudarUnidade = unidade => {
  const valor = props.modelValue?.valor;
  emit('update:modelValue', {
    ...(props.modelValue || {}),
    unidade,
    ...(Number.isInteger(valor) && { valor: Math.min(valor, tetoDa(unidade)) }),
  });
};
</script>

<template>
  <fieldset class="flex flex-col gap-1.5" data-peca="duracao">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <div class="flex flex-wrap items-start gap-3">
      <Input
        :id="id"
        :model-value="String(modelValue?.valor ?? '')"
        type="number"
        min="1"
        :max="maximo"
        class="w-28"
        :aria-label="rotulo"
        @update:model-value="novo => mudar('valor', lerNumero(novo))"
      />
      <ChoiceSelect
        :model-value="modelValue?.unidade || ''"
        :aria-label="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.UNIDADE')"
        :options="opcoes"
        @update:model-value="mudarUnidade"
      />
    </div>
  </fieldset>
</template>
