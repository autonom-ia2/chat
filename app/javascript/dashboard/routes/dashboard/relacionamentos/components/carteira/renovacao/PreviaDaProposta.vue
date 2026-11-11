<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../../comum/TituloDoDialogo.vue';
import { useTextosDoSeguro } from '../../../carteira/useTextosDoSeguro';
import PreviaDeMensagem from './PreviaDeMensagem.vue';

// #2897 — a conferência antes de a proposta sair: a mensagem como vai chegar
// no WhatsApp, com o PDF que vai junto, e os botões Enviar e Voltar. Só existe
// para quem escolheu conferir; com "sai sozinha" a proposta nem passa por aqui.
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

const previa = computed(() => {
  const { seguro } = props;
  const proposta = seguro?.renovacao?.proposta;
  if (!proposta) return null;
  const tipoDoPdf = proposta.oficial ? 'PROPOSTA' : 'RESUMO';
  return {
    titulo: tp('TITULO', { nome: seguro.pessoa.name }),
    arquivo: tp(`ARQUIVO_${tipoDoPdf}`),
    texto: tp(`MENSAGEM_${tipoDoPdf}`, {
      nome: seguro.pessoa.name.split(' ')[0],
      tipo: textos.tipo(seguro),
      seguradora: proposta.seguradora ?? seguro.seguradora,
      valor: textos.valor(proposta.valor),
    }),
  };
});

defineExpose({
  abrir: () => dialogo.value?.open(),
  fechar: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog ref="dialogo" width="sm" @confirm="emit('enviar')">
    <div v-if="previa" data-carteira="previa-envio" class="flex flex-col gap-4">
      <TituloDoDialogo :titulo="previa.titulo" :aviso="tp('APOIO')" />
      <PreviaDeMensagem :texto="previa.texto" :arquivo="previa.arquivo" />
    </div>
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          class="w-full"
          type="button"
          :label="tp('VOLTAR')"
          @click="dialogo?.close()"
        />
        <Button
          data-carteira="enviar"
          class="w-full"
          type="submit"
          :is-loading="enviando"
          :disabled="enviando"
          :label="tp('ENVIAR')"
        />
      </div>
    </template>
  </Dialog>
</template>
