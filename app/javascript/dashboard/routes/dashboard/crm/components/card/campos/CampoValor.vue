<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Input from 'dashboard/components-next/input/Input.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { MOEDAS } from '../useCardNegocio';

// #1423 — "Quanto vale": a moeda numa lista de escolha e o valor ao lado. O
// mesmo campo na criação e no Negócio (OB-06), nunca o código digitado.
defineProps({
  somenteLeitura: { type: Boolean, default: false },
  // #1498 — "Valor a receber" na Cobrança.
  rotulo: { type: String, default: '' },
});
const valor = defineModel('valor', { type: [String, Number], default: '' });
const moeda = defineModel('moeda', { type: String, default: 'BRL' });

const { t, te } = useI18n();
const N = 'CRM_CARD.NEGOCIO';
const moedas = computed(() =>
  [...new Set([...MOEDAS, moeda.value || 'BRL'])].map(codigo => ({
    value: codigo,
    label: te(`${N}.MOEDA.${codigo}`) ? t(`${N}.MOEDA.${codigo}`) : codigo,
  }))
);
</script>

<template>
  <div class="flex flex-col gap-1" data-campo-valor>
    <span class="text-sm font-medium text-n-slate-12">
      {{ rotulo || t(`${N}.VALOR`) }}
    </span>
    <div class="grid grid-cols-[minmax(0,9rem)_minmax(0,1fr)] gap-2">
      <ChoiceSelect
        v-model="moeda"
        :options="moedas"
        :disabled="somenteLeitura"
        :aria-label="t(`${N}.MOEDA_ROTULO`)"
        class="w-full"
      />
      <Input
        v-model="valor"
        type="number"
        min="0"
        step="0.01"
        :readonly="somenteLeitura"
        :aria-label="rotulo || t(`${N}.VALOR`)"
        :placeholder="t(`${N}.VALOR_EXEMPLO`)"
      />
    </div>
  </div>
</template>
