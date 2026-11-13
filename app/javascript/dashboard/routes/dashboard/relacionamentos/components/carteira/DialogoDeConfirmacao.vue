<script setup>
import { useTemplateRef } from 'vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';

// #2897 — a pergunta antes de um passo sem volta na gaveta do seguro: apagar o
// PDF, trocar o PDF que já está guardado e sair do Corrigir sem salvar. Os
// textos vêm de quem usa. Tocar fora não fecha (só Esc e o botão de voltar).
// Quem usa age ao ouvir `confirmar` e fecha o diálogo (`fechar`) quando deu
// certo; se não deu, passa a frase em `alerta` e o diálogo continua aberto, com
// ela dentro.
defineProps({
  // O `data-carteira` do diálogo.
  marca: { type: String, required: true },
  titulo: { type: String, required: true },
  aviso: { type: String, required: true },
  confirmar: { type: String, required: true },
  voltar: { type: String, required: true },
  ocupado: { type: Boolean, default: false },
  alerta: { type: String, default: '' },
});
const emit = defineEmits(['confirmar', 'fechou']);

const dialogo = useTemplateRef('dialogo');

defineExpose({
  abrir: () => dialogo.value?.open(),
  fechar: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog
    ref="dialogo"
    type="alert"
    width="sm"
    :confirm-button-label="confirmar"
    :cancel-button-label="voltar"
    :is-loading="ocupado"
    :close-on-outside-click="false"
    @confirm="emit('confirmar')"
    @close="emit('fechou')"
  >
    <div :data-carteira="marca" class="flex flex-col gap-3">
      <TituloDoDialogo :titulo="titulo" :aviso="aviso" />
      <p
        v-if="alerta"
        role="alert"
        data-carteira="alerta-do-dialogo"
        class="m-0 text-base font-medium text-n-ruby-11"
      >
        {{ alerta }}
      </p>
    </div>
  </Dialog>
</template>
