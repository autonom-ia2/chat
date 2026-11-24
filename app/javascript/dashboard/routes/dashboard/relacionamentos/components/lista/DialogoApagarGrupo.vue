<script setup>
import { ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';

// #3168 — "Apagar grupo": confirmação destrutiva (Apagar em vermelho). Diz que
// as pessoas ficam; some só o grupo. Tocar fora não fecha (só Esc e Cancelar).
// Quem apaga é a tela, por `apagar`; ela fecha o diálogo com `fechar()`.
defineProps({
  apagando: { type: Boolean, default: false },
});
const emit = defineEmits(['apagar']);

const { t } = useI18n();
const MG = 'RELACIONAMENTOS.LISTA.MEUS_GRUPOS';
const dialogo = useTemplateRef('dialogo');
const nome = ref('');

const abrir = nomeDoGrupo => {
  nome.value = nomeDoGrupo;
  dialogo.value?.open();
};
const fechar = () => dialogo.value?.close();

defineExpose({ abrir, fechar });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="sm"
    :confirm-button-label="t(`${MG}.APAGAR_CONFIRMAR`)"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :is-loading="apagando"
    :close-on-outside-click="false"
    @confirm="emit('apagar')"
  >
    <div data-relacionamentos="dialogo-apagar-grupo">
      <TituloDoDialogo
        :titulo="t(`${MG}.APAGAR_TITULO`, { nome })"
        :aviso="t(`${MG}.APAGAR_AVISO`)"
      />
    </div>
  </Dialog>
</template>
