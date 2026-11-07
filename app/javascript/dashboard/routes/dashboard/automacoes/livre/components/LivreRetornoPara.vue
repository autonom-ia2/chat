<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import LivreMarcar from './LivreMarcar.vue';
import { QUEM } from '../retorno';

// G3 (#2629) — quem recebe o retorno: o responsável, pessoas escolhidas ou um
// time. A plataforma confere, ao criar, quem pode receber; aqui só se escolhe.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: null },
  opcoes: { type: Object, required: true },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const R = 'AUTOMACAO_LIVRE.RETORNO';
const quem = computed(() => props.modelValue?.quem || 'responsavel');
const opcoesDeQuem = computed(() =>
  QUEM.map(valor => ({
    value: valor,
    label: t(`${R}.OPCOES.${valor.toUpperCase()}`),
  }))
);

const trocarQuem = valor => emit('update:modelValue', { quem: valor });
</script>

<template>
  <fieldset class="flex flex-col gap-4" data-peca="quem_recebe_retorno">
    <legend class="mb-1.5 text-sm font-medium text-n-slate-12">
      {{ rotulo }}
    </legend>
    <ChoiceSelect
      data-quem
      :model-value="quem"
      :aria-label="rotulo"
      :options="opcoesDeQuem"
      @update:model-value="trocarQuem"
    />
    <LivreMarcar
      v-if="quem === 'pessoas'"
      data-pessoas
      :rotulo="$t(`${R}.PESSOAS`)"
      :opcoes="opcoes.pessoa || []"
      :model-value="modelValue?.pessoas || []"
      @update:model-value="
        valor => emit('update:modelValue', { quem, pessoas: valor })
      "
    />
    <div v-if="quem === 'time'" class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${R}.TIME`) }}
      </span>
      <ChoiceSelect
        data-time
        :model-value="modelValue?.time ?? ''"
        :aria-label="$t(`${R}.TIME`)"
        :placeholder="$t(`${R}.ESCOLHA`)"
        :options="opcoes.time || []"
        @update:model-value="
          valor => emit('update:modelValue', { quem, time: valor })
        "
      />
    </div>
  </fieldset>
</template>
