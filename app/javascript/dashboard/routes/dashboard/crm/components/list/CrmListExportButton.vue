<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import Button from 'dashboard/components-next/button/Button.vue';

// #722 — "Exportar" da Lista do CRM: baixa um .xlsx com o funil, os filtros, a busca,
// o resultado e a ordenação que a Lista mostra agora, sem o limite de página. Quem
// monta os parâmetros é o store (listQueryParams), o mesmo caminho da Lista.
const props = defineProps({
  pipelineId: { type: [Number, String], default: null },
  sortParams: { type: Object, default: () => ({}) },
  disabled: { type: Boolean, default: false },
});

const { t } = useI18n();
const store = useStore();
const isExporting = ref(false);

const baixar = (blob, filename) => {
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.setAttribute('href', url);
  link.setAttribute('download', filename);
  link.click();
  URL.revokeObjectURL(url);
};

const exportar = async () => {
  if (!props.pipelineId || isExporting.value) return;
  isExporting.value = true;
  try {
    const { blob, filename } = await store.dispatch(
      'crmKanban/exportCardsList',
      { pipelineId: props.pipelineId, ...props.sortParams }
    );
    baixar(blob, filename);
  } catch {
    useAlert(t('CRM_KANBAN.ACTIONS.EXPORT_ERROR'));
  } finally {
    isExporting.value = false;
  }
};
</script>

<template>
  <Button
    data-crm-exportar
    icon="i-lucide-file-spreadsheet"
    :label="t('CRM_KANBAN.ACTIONS.EXPORT')"
    :title="t('CRM_KANBAN.ACTIONS.EXPORT_TITLE')"
    slate
    faded
    :is-loading="isExporting"
    :disabled="disabled || !pipelineId || isExporting"
    @click="exportar"
  />
</template>
