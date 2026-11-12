<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import DialogoDePrevia from './DialogoDePrevia.vue';

// #2897 — a conferência antes de a proposta sair: a mensagem como vai chegar
// no WhatsApp, com o PDF que vai junto, e os botões Enviar e Voltar. Só existe
// para quem escolheu conferir; com "sai sozinha" a proposta nem passa por aqui.
// O que vai junto é a proposta oficial ou, quando ela não existe (a seguradora
// não tem proposta em PDF, ou ninguém a pediu ainda), o resumo da cotação, com
// preço e coberturas; o título diz qual dos dois. Se a pessoa não escreve há
// mais de um dia, o WhatsApp só deixa sair o texto aprovado: a prévia mostra
// esse texto (que fala em proposta) e diz por quê.
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

// O PDF que vai junto: a proposta oficial ou o resumo da cotação.
const pdfDa = proposta =>
  proposta.oficial && !proposta.semPdf ? 'PROPOSTA' : 'RESUMO';

const previa = computed(() => {
  const { seguro } = props;
  const proposta = seguro?.renovacao?.proposta;
  if (!proposta) return null;
  const nome = seguro.pessoa.name.split(' ')[0];
  const tipo = textos.tipo(seguro);
  if (seguro.foraDaJanela) {
    return {
      titulo: tp('TITULO_PROPOSTA', { nome: seguro.pessoa.name }),
      arquivo: '',
      nota: tp('FORA_DA_JANELA', { nome }),
      texto: tp('MENSAGEM_MODELO', { nome, tipo }),
    };
  }
  const pdf = pdfDa(proposta);
  return {
    titulo: tp(`TITULO_${pdf}`, { nome: seguro.pessoa.name }),
    arquivo: tp(`ARQUIVO_${pdf}`),
    nota: '',
    texto: tp(`MENSAGEM_${pdf}`, {
      nome,
      tipo,
      seguradora: proposta.seguradora ?? seguro.seguradora,
      preco: textos.valor(proposta.valor),
      periodo: textos.periodo(proposta),
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
    :nota="previa?.nota"
    :enviando="enviando"
    @enviar="emit('enviar')"
  />
</template>
