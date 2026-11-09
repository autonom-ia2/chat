<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// G62 (#2829) — campo do card do tipo "pessoa da equipe": escolhe uma pessoa
// da conta e guarda o id dela. O motor confere que a pessoa é da conta.
const props = defineProps({
  attribute: { type: Object, required: true },
  pessoas: { type: Array, default: () => [] },
});

const emit = defineEmits(['update', 'delete']);
const { t } = useI18n();

const opcoes = computed(() =>
  props.pessoas.map(pessoa => ({ value: pessoa.id, label: pessoa.name }))
);
const escolhida = computed({
  get: () => {
    const id = Number(props.attribute.value);
    return Number.isInteger(id) && id > 0 ? id : null;
  },
  set: id => emit('update', id),
});
</script>

<template>
  <div class="flex items-center w-full min-w-0 gap-2" data-campo-pessoa>
    <ChoiceSelect
      v-model="escolhida"
      :options="opcoes"
      :aria-label="attribute.attributeDisplayName"
      :placeholder="t('CRM_KANBAN.DRAWER.CARD_FIELDS.ESCOLHER_PESSOA')"
      compact
      class="flex-1 min-w-0"
    />
    <Button
      v-if="escolhida"
      variant="faded"
      color="ruby"
      icon="i-lucide-trash"
      size="xs"
      class="flex-shrink-0 opacity-0 group-hover/attribute:opacity-100 hover:no-underline"
      :aria-label="t('CRM_KANBAN.DRAWER.CARD_FIELDS.LIMPAR_PESSOA')"
      @click="emit('delete')"
    />
  </div>
</template>
