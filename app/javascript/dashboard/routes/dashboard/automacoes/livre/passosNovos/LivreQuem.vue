<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { P, QUEM } from './passosNovos';

// #2931 e #2935 — quem aprova o pedido ou em qual agenda a reunião entra: quem
// cuida do card (o padrão), uma pessoa ou um time. A pessoa e o time vêm das
// escolhas da conta. O motor confere, na hora, quem alcança o registro.
const props = defineProps({
  rotulo: { type: String, required: true },
  modelValue: { type: Object, default: () => ({ de: 'responsavel' }) },
  opcoes: { type: Object, required: true },
  // A reunião é de uma pessoa: o time não entra.
  semTime: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const tipos = computed(() =>
  QUEM.filter(de => !(props.semTime && de === 'time')).map(de => ({
    value: de,
    label: t(`${P}.QUEM.${de.toUpperCase()}`),
  }))
);
const lista = computed(() =>
  props.modelValue?.de === 'time' ? props.opcoes.time : props.opcoes.pessoa
);
const escolherDe = de =>
  emit('update:modelValue', de === 'responsavel' ? { de } : { de, id: null });
const escolherId = id =>
  emit('update:modelValue', { de: props.modelValue.de, id });
</script>

<template>
  <div class="flex flex-col gap-3" data-peca="quem">
    <div class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">{{ rotulo }}</span>
      <ChoiceSelect
        data-quem-de
        :model-value="modelValue?.de || 'responsavel'"
        :aria-label="rotulo"
        :options="tipos"
        @update:model-value="escolherDe"
      />
    </div>
    <div v-if="modelValue?.de !== 'responsavel'" class="flex flex-col gap-1.5">
      <span class="text-sm font-medium text-n-slate-12">
        {{ $t(`${P}.QUEM.QUAL_${modelValue.de.toUpperCase()}`) }}
      </span>
      <ChoiceSelect
        v-if="lista?.length"
        data-quem-id
        :model-value="modelValue.id ?? ''"
        :aria-label="$t(`${P}.QUEM.QUAL_${modelValue.de.toUpperCase()}`)"
        :placeholder="$t('AUTOMACAO_LIVRE.ALTERAR_PAINEL.ESCOLHA')"
        :options="lista"
        @update:model-value="escolherId"
      />
      <p v-else data-quem-vazio class="mb-0 text-sm text-n-slate-11">
        {{ $t(`${P}.QUEM.NINGUEM`) }}
      </p>
    </div>
  </div>
</template>
