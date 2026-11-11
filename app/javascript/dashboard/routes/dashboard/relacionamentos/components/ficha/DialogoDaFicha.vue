<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';

// #2894 — o diálogo de confirmação da ficha: título com peso de título (o
// `Dialog` da casa escreve o título pequeno), um texto, "Cancelar" discreto e o
// botão principal. `marcaConfirmar` põe o `data-relacionamentos` do botão
// principal, para o robô de print. O corpo extra vai no slot `default`.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  confirmar: { type: String, required: true },
  cancelar: { type: String, required: true },
  marcaConfirmar: { type: String, default: '' },
  carregando: { type: Boolean, default: false },
  desligado: { type: Boolean, default: false },
});
const emit = defineEmits(['confirm']);

const dialogo = ref(null);
defineExpose({
  open: () => dialogo.value?.open(),
  close: () => dialogo.value?.close(),
});
</script>

<template>
  <Dialog ref="dialogo" width="sm" @confirm="emit('confirm')">
    <TituloDoDialogo :titulo="titulo" :aviso="texto" />
    <slot />
    <template #footer>
      <div class="flex items-center justify-between w-full gap-3">
        <Button
          variant="faded"
          color="slate"
          class="w-full"
          type="button"
          :label="cancelar"
          @click="dialogo?.close()"
        />
        <Button
          :data-relacionamentos="marcaConfirmar || undefined"
          class="w-full"
          type="submit"
          :is-loading="carregando"
          :disabled="carregando || desligado"
          :label="confirmar"
        />
      </div>
    </template>
  </Dialog>
</template>
