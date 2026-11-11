<script setup>
import { ref } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import TituloDoDialogo from '../comum/TituloDoDialogo.vue';

// #2894 — o diálogo de confirmação da ficha: título com peso de título (o
// `Dialog` da casa escreve o título pequeno), um texto, "Cancelar" discreto e o
// botão principal. `marcaConfirmar` põe o `data-relacionamentos` do botão
// principal, para o robô de print. O corpo extra vai no slot `default`. Com
// `soEntendi` o diálogo só explica: um botão "Entendi" que fecha (sem confirmar).
// Nenhum botão fica desligado por falta de algo; só `carregando` o desliga.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  confirmar: { type: String, default: '' },
  cancelar: { type: String, default: '' },
  entendi: { type: String, default: '' },
  marcaConfirmar: { type: String, default: '' },
  carregando: { type: Boolean, default: false },
  soEntendi: { type: Boolean, default: false },
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
      <div v-if="soEntendi" class="flex w-full">
        <Button
          data-relacionamentos="entendi"
          class="w-full"
          type="button"
          :label="entendi"
          @click="dialogo?.close()"
        />
      </div>
      <div v-else class="flex items-center justify-between w-full gap-3">
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
          :disabled="carregando"
          :label="confirmar"
        />
      </div>
    </template>
  </Dialog>
</template>
