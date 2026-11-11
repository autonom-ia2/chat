<script setup>
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { contaDaMensagem } from '../../lista/quemFicaDeFora';

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

const conta = computed(() => contaDaMensagem(props.pessoas));

const motivos = computed(() => {
  const { naoQuer, semTelefone } = conta.value;
  return [
    [naoQuer, 'MOTIVO_NAO_QUER'],
    [semTelefone, 'MOTIVO_SEM_TELEFONE'],
  ]
    .filter(([quantos]) => quantos > 0)
    .map(([count, chave]) =>
      t(`RELACIONAMENTOS.LISTA.MENSAGEM.${chave}`, { count }, count)
    );
});

const frases = computed(() => {
  const { recebem, fora } = conta.value;
  const base = recebem
    ? t('RELACIONAMENTOS.LISTA.MENSAGEM.RECEBEM', { count: recebem }, recebem)
    : t('RELACIONAMENTOS.LISTA.MENSAGEM.NINGUEM_RECEBE');
  if (!fora) return [base];
  const deFora = t(
    'RELACIONAMENTOS.LISTA.MENSAGEM.FORA',
    { count: fora, motivos: motivos.value.join(', ') },
    fora
  );
  return [base, deFora];
});

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
    :title="t('RELACIONAMENTOS.LISTA.MENSAGEM.TITULO')"
    :confirm-button-label="t('RELACIONAMENTOS.COMUM.CONTINUAR')"
    :cancel-button-label="t('RELACIONAMENTOS.COMUM.CANCELAR')"
    :disable-confirm-button="conta.recebem === 0"
    @confirm="continuar"
  >
    <p
      data-relacionamentos="dialogo-mensagem"
      class="m-0 text-base text-n-slate-12"
    >
      {{ frases.join(' ') }}
    </p>
  </Dialog>
</template>
