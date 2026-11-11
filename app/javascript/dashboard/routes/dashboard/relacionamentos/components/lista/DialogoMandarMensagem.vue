<script setup>
import { computed, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';
import { nomesQueRecebem } from '../../lista/nomesQueRecebem';
import { motivosEmPalavras } from '../../lista/motivosEmPalavras';
import { contaDaMensagem } from '../../lista/quemFicaDeFora';

// #2894 — "12 pessoas vão receber. 2 ficam de fora: 1 pediu para não receber,
// 1 está sem telefone." Quem tem telefone e não pediu para parar recebe; quem
// fica de fora aparece com o motivo. Continuar entrega a quantidade a quem
// usa, que abre a campanha.
const props = defineProps({
  pessoas: { type: Array, required: true },
});
const emit = defineEmits(['continuar']);

const { t, locale } = useI18n();
const dialogo = useTemplateRef('dialogo');

const conta = computed(() => contaDaMensagem(props.pessoas));

// "Vânia, Nádia e mais 40": o idioma da tela (pt_BR -> pt-BR) escolhe o "e".
const quemRecebe = computed(() =>
  nomesQueRecebem(props.pessoas, {
    idioma: locale.value.replace('_', '-'),
    eMais: count =>
      t('RELACIONAMENTOS.LISTA.MENSAGEM.E_MAIS', { count }, count),
  })
);

const frases = computed(() => {
  const { recebem, fora } = conta.value;
  if (recebem === 0) {
    return [
      t('RELACIONAMENTOS.LISTA.MENSAGEM.NINGUEM_PODE', {
        motivos: motivosEmPalavras(t, conta.value).join(', '),
      }),
    ];
  }
  const base = t(
    'RELACIONAMENTOS.LISTA.MENSAGEM.QUEM_RECEBE',
    { quem: quemRecebe.value },
    recebem
  );
  if (!fora) return [base];
  const motivos = motivosEmPalavras(t, conta.value, 'MOTIVO').join(', ');
  return [
    base,
    t('RELACIONAMENTOS.LISTA.MENSAGEM.FORA', { count: fora, motivos }, fora),
  ];
});

// Sem ninguém de fora e com quem receba: só falta dizer o que vem depois.
const contaSemNinguemDeFora = computed(
  () => conta.value.fora === 0 && conta.value.recebem > 0
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
        v-if="contaSemNinguemDeFora"
        data-relacionamentos="dialogo-mensagem-proximo"
        class="m-0 text-sm text-n-slate-11"
      >
        {{ t('RELACIONAMENTOS.LISTA.MENSAGEM.PROXIMO_PASSO') }}
      </p>
    </div>
  </Dialog>
</template>
