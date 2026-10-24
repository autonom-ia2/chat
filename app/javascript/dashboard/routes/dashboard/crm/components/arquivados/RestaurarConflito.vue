<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';

// Restaurar quando o cliente já tem outro card aberto no mesmo funil (#2095, decisão 9 revisada). O sistema não sabe
// por que o outro card existe: a janela só mostra qual é (título e etapa) e deixa a pessoa decidir. O principal é
// abrir o card aberto; restaurar mesmo assim deixa dois abertos do mesmo cliente.
const props = defineProps({
  // { nome, funil, aberto: { id, title, stage_name } }
  conflito: { type: Object, default: null },
  ocupado: { type: Boolean, default: false },
  erro: { type: String, default: '' },
});
const emit = defineEmits(['abrirAberto', 'restaurarMesmoAssim', 'close']);

const { t } = useI18n();
const dialogo = ref(null);

const titulo = computed(() =>
  t('CRM_ARQUIVADOS.CONFLITO.TITULO', { nome: props.conflito?.nome || '' })
);
const texto = computed(() =>
  t('CRM_ARQUIVADOS.CONFLITO.TEXTO', {
    titulo: props.conflito?.aberto?.title || '',
    funil: props.conflito?.funil || '',
    etapa: props.conflito?.aberto?.stage_name || '',
  })
);

defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog
    ref="dialogo"
    data-restaurar-conflito
    type="edit"
    :title="titulo"
    :description="texto"
    width="md"
    @close="emit('close')"
  >
    <p
      v-if="erro"
      role="alert"
      class="mb-0 rounded-lg bg-n-ruby-2 px-3 py-2 text-sm text-n-ruby-11"
    >
      {{ erro }}
    </p>
    <template #footer>
      <div class="flex flex-wrap justify-end gap-2">
        <Button
          type="button"
          data-conflito-forcar
          :label="t('CRM_ARQUIVADOS.CONFLITO.MESMO_ASSIM')"
          slate
          faded
          class="!min-h-11"
          :is-loading="ocupado"
          :disabled="ocupado"
          @click="emit('restaurarMesmoAssim')"
        />
        <Button
          type="button"
          data-conflito-abrir
          autofocus
          :label="t('CRM_ARQUIVADOS.CONFLITO.ABRIR_ABERTO')"
          icon="i-lucide-square-arrow-out-up-right"
          class="!min-h-11"
          :disabled="ocupado"
          @click="emit('abrirAberto')"
        />
      </div>
    </template>
  </Dialog>
</template>
