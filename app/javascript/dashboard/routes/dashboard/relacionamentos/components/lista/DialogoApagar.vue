<script setup>
import { useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useEnvio } from '../../lista/useEnvio';

// #2894 — confirmação destrutiva: "Apagar 12 pessoas? Isto não volta." Tocar
// fora não fecha (só Esc e Cancelar). No protótipo só simula.
const props = defineProps({
  pessoas: { type: Array, required: true },
  acoes: { type: Object, required: true },
});
const emit = defineEmits(['concluido']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const { enviando, enviar } = useEnvio(() =>
  t('RELACIONAMENTOS.LISTA.APAGAR.ERRO')
);

const apagar = async () => {
  const feito = await enviar(() =>
    props.acoes.apagar({ pessoas: props.pessoas })
  );
  if (!feito) return;
  useAlert(
    t(
      'RELACIONAMENTOS.LISTA.APAGAR.APAGADAS',
      { count: feito.apagadas },
      feito.apagadas
    )
  );
  dialogo.value?.close();
  emit('concluido');
};

defineExpose({ abrir: () => dialogo.value?.open() });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="sm"
    :title="
      t(
        'RELACIONAMENTOS.LISTA.APAGAR.TITULO',
        { count: pessoas.length },
        pessoas.length
      )
    "
    :description="t('RELACIONAMENTOS.LISTA.APAGAR.AVISO')"
    :confirm-button-label="t('RELACIONAMENTOS.LISTA.APAGAR.CONFIRMAR')"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :is-loading="enviando"
    :close-on-outside-click="false"
    @confirm="apagar"
  />
</template>
