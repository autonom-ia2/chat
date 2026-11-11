<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import DialogoDePrevia from './DialogoDePrevia.vue';

// #2897 — a conferência antes de a proposta sair: a mensagem como vai chegar
// no WhatsApp, com o PDF que vai junto, e os botões Enviar e Voltar. Só existe
// para quem escolheu conferir; com "sai sozinha" a proposta nem passa por aqui.
// Quando o preço chegou e o PDF não veio, vai só o preço: sem arquivo.
const props = defineProps({
  seguro: { type: Object, default: null },
  enviando: { type: Boolean, default: false },
});
const emit = defineEmits(['enviar']);

const { t } = useI18n();
const tp = (chave, valores) =>
  t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.PREVIA.${chave}`, valores);
const textos = useTextosDoSeguro();
const dialogo = ref(null);

// O PDF que vai junto: a proposta, o resumo ou nenhum ('').
const pdfDa = proposta => {
  if (proposta.semPdf) return '';
  return proposta.oficial ? 'PROPOSTA' : 'RESUMO';
};

const previa = computed(() => {
  const { seguro } = props;
  const proposta = seguro?.renovacao?.proposta;
  if (!proposta) return null;
  const pdf = pdfDa(proposta);
  return {
    titulo: tp('TITULO', { nome: seguro.pessoa.name }),
    arquivo: pdf ? tp(`ARQUIVO_${pdf}`) : '',
    texto: tp(`MENSAGEM_${pdf || 'SEM_PDF'}`, {
      nome: seguro.pessoa.name.split(' ')[0],
      tipo: textos.tipo(seguro),
      seguradora: proposta.seguradora ?? seguro.seguradora,
      valor: textos.valor(proposta.valor),
    }),
  };
});

defineExpose({
  abrir: () => dialogo.value?.abrir(),
  fechar: () => dialogo.value?.fechar(),
});
</script>

<template>
  <DialogoDePrevia
    ref="dialogo"
    :titulo="previa?.titulo"
    :texto="previa?.texto"
    :arquivo="previa?.arquivo"
    :enviando="enviando"
    @enviar="emit('enviar')"
  />
</template>
