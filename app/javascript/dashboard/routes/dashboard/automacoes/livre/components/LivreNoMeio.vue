<script setup>
import { ref } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';

// #2414 F0 — mudar uma automação ligada com gente no meio: quem já começou
// termina na versão de antes (o padrão, ADR D10) ou para agora.
defineProps({
  quantas: { type: Number, required: true },
});

const emit = defineEmits(['confirmar', 'close']);

const dialog = ref(null);
const escolha = ref('terminam');

const open = () => {
  escolha.value = 'terminam';
  dialog.value?.open();
};

const confirmar = () => {
  dialog.value?.close();
  emit('confirmar', escolha.value);
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    :title="$t('AUTOMACAO_LIVRE.NO_MEIO.TITULO', { n: quantas }, quantas)"
    :confirm-button-label="$t('AUTOMACAO_LIVRE.NO_MEIO.SALVAR')"
    :cancel-button-label="$t('AUTOMACAO_LIVRE.NO_MEIO.CANCELAR')"
    @confirm="confirmar"
    @close="emit('close')"
  >
    <div data-no-meio class="flex flex-col gap-3">
      <RadioCard
        id="no-meio-terminam"
        name="no-meio"
        :label="$t('AUTOMACAO_LIVRE.NO_MEIO.TERMINAM')"
        :description="$t('AUTOMACAO_LIVRE.NO_MEIO.TERMINAM_TEXTO')"
        :is-active="escolha === 'terminam'"
        @select="escolha = 'terminam'"
      />
      <RadioCard
        id="no-meio-param"
        name="no-meio"
        :label="$t('AUTOMACAO_LIVRE.NO_MEIO.PARAM')"
        :description="$t('AUTOMACAO_LIVRE.NO_MEIO.PARAM_TEXTO')"
        :is-active="escolha === 'param'"
        @select="escolha = 'param'"
      />
    </div>
  </Dialog>
</template>
