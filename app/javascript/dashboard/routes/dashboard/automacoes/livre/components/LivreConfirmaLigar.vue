<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { custoPorVez, temSemVolta, usaIA } from '../prototipo/receita';
import { dinheiro } from '../prototipo/frases';

// #2414 F0 — ligar é um botão. Se a automação manda algo ao cliente (sem volta)
// ou usa a IA, uma frase pede o OK antes. Sem nada disso, liga direto.
const emit = defineEmits(['ligar', 'close']);

const { t } = useI18n();
const dialog = ref(null);
const receita = ref(null);
const quem = ref(null);

const frase = computed(() => {
  const mensagem = temSemVolta(receita.value);
  const ia = usaIA(receita.value);
  const custo = dinheiro(custoPorVez(receita.value));
  if (mensagem && ia)
    return t('AUTOMACAO_LIVRE.LIGAR.CONFIRMA_TUDO', { custo });
  if (ia) return t('AUTOMACAO_LIVRE.LIGAR.CONFIRMA_IA', { custo });
  return t('AUTOMACAO_LIVRE.LIGAR.CONFIRMA_MENSAGEM');
});

// Devolve true se abriu a confirmação; false se já ligou.
const pedir = (receitaParaLigar, alvo = null) => {
  receita.value = receitaParaLigar;
  quem.value = alvo;
  if (!temSemVolta(receitaParaLigar) && !usaIA(receitaParaLigar)) {
    emit('ligar', alvo);
    return false;
  }
  dialog.value?.open();
  return true;
};

const confirmar = () => {
  dialog.value?.close();
  emit('ligar', quem.value);
};

defineExpose({ pedir });
</script>

<template>
  <Dialog
    ref="dialog"
    type="alert"
    :title="$t('AUTOMACAO_LIVRE.LIGAR.TITULO')"
    :description="frase"
    :confirm-button-label="$t('AUTOMACAO_LIVRE.LIGAR.SIM')"
    :cancel-button-label="$t('AUTOMACAO_LIVRE.LIGAR.AINDA_NAO')"
    @confirm="confirmar"
    @close="emit('close')"
  />
</template>
