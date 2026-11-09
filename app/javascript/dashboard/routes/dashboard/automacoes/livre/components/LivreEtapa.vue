<script setup>
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2414 G4 — a etapa em que o passo "criar card" abre o card, agrupada pelo
// funil, da mesma lista do gatilho de card (useEscolhasDosGatilhos).
defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Number, default: null },
  // [{ label: funil, options: [{ value: id, label: etapa }] }]
  grupos: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);
</script>

<template>
  <div class="flex flex-col gap-1.5" data-peca="etapa">
    <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
    <ChoiceSelect
      :model-value="modelValue ?? ''"
      :aria-label="rotulo"
      :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
      :groups="grupos"
      @update:model-value="valor => emit('update:modelValue', valor)"
    />
  </div>
</template>
