<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreDuracao from './LivreDuracao.vue';
import { SEM_PRAZO } from '../receita';

// #2750 — o prazo do "Esperar até": até um prazo (quanto tempo) ou sem prazo,
// quando a espera só termina pela condição. A escolha é explícita: o passo
// nasce com prazo, e "Sem prazo" é uma opção da lista, nunca um número alto.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: [Object, String], default: null },
  unidades: { type: Array, required: true },
  // O passo já tem passos em "Se o prazo acabar": sem prazo, eles nunca
  // rodariam, e o "Salvar" espera a pessoa tirá-los.
  temSeVencer: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const COM = 'com_prazo';
const semPrazo = computed(() => props.modelValue === SEM_PRAZO);
// Volta para o último prazo escrito quando a pessoa desfaz o "Sem prazo".
const ultimo = ref(
  semPrazo.value ? { valor: 1, unidade: 'dias' } : props.modelValue
);

const opcoes = computed(() => [
  { value: COM, label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.COM_PRAZO') },
  { value: SEM_PRAZO, label: t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO') },
]);

const escolher = novo =>
  emit(
    'update:modelValue',
    novo === SEM_PRAZO
      ? SEM_PRAZO
      : ultimo.value || { valor: 1, unidade: 'dias' }
  );

const mudarDuracao = novo => {
  ultimo.value = novo;
  emit('update:modelValue', novo);
};
</script>

<template>
  <div class="flex flex-col gap-3" data-peca="prazo">
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <ChoiceSelect
        :model-value="semPrazo ? SEM_PRAZO : COM"
        :aria-label="rotulo"
        :options="opcoes"
        @update:model-value="escolher"
      />
    </div>
    <LivreDuracao
      v-if="!semPrazo"
      :rotulo="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.QUANTO_TEMPO')"
      :model-value="modelValue"
      :unidades="unidades"
      @update:model-value="mudarDuracao"
    />
    <template v-else>
      <p class="mb-0 text-sm text-n-slate-11" data-sem-prazo-dica>
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO_DICA') }}
      </p>
      <p
        v-if="temSeVencer"
        class="mb-0 text-sm text-n-ruby-11"
        data-sem-prazo-se-vencer
      >
        {{ $t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.SEM_PRAZO_TIRE_SE_VENCER') }}
      </p>
    </template>
  </div>
</template>
