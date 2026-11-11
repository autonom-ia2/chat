<script setup>
import { useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { useFrasesDaMensagem } from '../../lista/useFrasesDaMensagem';

// #2894 — "12 pessoas vão receber. 2 ficam de fora: 1 pediu para não receber,
// 1 está sem telefone." Quem tem telefone e não pediu para parar recebe; quem
// fica de fora aparece com o motivo. Continuar entrega a quantidade a quem
// usa, que abre a campanha.
const props = defineProps({
  pessoas: { type: Array, required: true },
});
const emit = defineEmits(['continuar']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');

const { conta, frases, alguemRecebe } = useFrasesDaMensagem(
  () => props.pessoas
);

const continuar = () => {
  emit('continuar', conta.value.recebem);
  dialogo.value?.close();
};

defineExpose({ abrir: () => dialogo.value?.open() });
</script>

<template>
  <Dialog
    ref="dialogo"
    type="edit"
    width="md"
    :confirm-button-label="t('RELACIONAMENTOS.COMUM.CONTINUAR')"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :disable-confirm-button="conta.recebem === 0"
    @confirm="continuar"
  >
    <TituloDoDialogo :titulo="t('RELACIONAMENTOS.LISTA.MENSAGEM.TITULO')" />
    <div class="flex flex-col gap-2">
      <p
        data-relacionamentos="dialogo-mensagem"
        class="m-0 text-base text-n-slate-12"
      >
        {{ frases.join(' ') }}
      </p>
      <p
        v-if="alguemRecebe"
        data-relacionamentos="dialogo-mensagem-proximo"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('RELACIONAMENTOS.LISTA.MENSAGEM.PROXIMO_PASSO') }}
      </p>
    </div>
  </Dialog>
</template>
