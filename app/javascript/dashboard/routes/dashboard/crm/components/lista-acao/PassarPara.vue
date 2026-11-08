<script setup>
import { nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';

// #2283 — "Alterar → Passar para alguém": a mesma escolha de pessoa da linha
// "Ninguém cuidando", numa janela. Grava só o dono do card (decisão 2).
const props = defineProps({
  pessoas: { type: Array, default: () => [] },
});
const emit = defineEmits(['passar']);

const { t } = useI18n();
const dialogo = useTemplateRef('dialogo');
const cliente = ref(null);
const escolhida = ref('');

const abrir = async (card, { nome }) => {
  cliente.value = { card, nome };
  escolhida.value = '';
  await nextTick();
  dialogo.value?.open();
};

const confirmar = () => {
  const pessoa = props.pessoas.find(
    item => String(item.value) === String(escolhida.value)
  );
  if (!pessoa) return;
  emit('passar', cliente.value.card, pessoa);
  dialogo.value?.close();
};

defineExpose({ abrir });
</script>

<template>
  <Dialog
    ref="dialogo"
    width="md"
    :title="t('CRM_LISTA_ACAO.PASSAR.TITULO', { nome: cliente?.nome })"
    :confirm-button-label="t('CRM_LISTA_ACAO.PASSAR.CONFIRMAR')"
    :cancel-button-label="t('CRM_LISTA_ACAO.COMBINAR.CANCELAR')"
    :disable-confirm-button="!escolhida"
    @confirm="confirmar"
  >
    <ChoiceSelect
      v-model="escolhida"
      :options="pessoas"
      :placeholder="t('CRM_LISTA_ACAO.PASSAR.ESCOLHER')"
      :aria-label="
        t('CRM_LISTA_ACAO.ACOES.ROTULO_PASSAR', { nome: cliente?.nome })
      "
      class="w-full [&>button]:!h-11 [&>button]:!w-full [&>button]:!rounded-xl"
    />
  </Dialog>
</template>
