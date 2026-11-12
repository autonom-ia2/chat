<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../../comum/TituloDoDialogo.vue';
import PreviaDeMensagem from './PreviaDeMensagem.vue';

// #2897 — a conferência antes de uma mensagem sair: como ela chega no WhatsApp
// (com o arquivo que vai junto, se houver) e os botões Voltar e Enviar. Quem
// usa diz o título e o texto: a proposta da renovação, o aviso da parcela. A
// `nota` é uma linha acima da mensagem, para o que a pessoa precisa saber antes
// de enviar (o WhatsApp só deixa sair o texto aprovado).
defineProps({
  titulo: { type: String, default: '' },
  texto: { type: String, default: '' },
  nota: { type: String, default: '' },
  arquivo: { type: String, default: '' },
  enviando: { type: Boolean, default: false },
});
const emit = defineEmits(['enviar']);

const { t } = useI18n();
const tp = chave => t(`RELACIONAMENTOS_CARTEIRA.RENOVACAO.PREVIA.${chave}`);
const dialogo = ref(null);

defineExpose({
  abrir: () => dialogo.value?.open(),
  fechar: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog ref="dialogo" width="sm" @confirm="emit('enviar')">
    <div v-if="texto" data-carteira="previa-envio" class="flex flex-col gap-4">
      <TituloDoDialogo :titulo="titulo" :aviso="tp('APOIO')" />
      <p
        v-if="nota"
        data-carteira="nota-da-previa"
        class="m-0 text-base text-n-slate-12"
      >
        {{ nota }}
      </p>
      <PreviaDeMensagem :texto="texto" :arquivo="arquivo" />
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
