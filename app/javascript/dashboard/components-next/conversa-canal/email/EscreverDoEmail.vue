<script setup>
// Gaveta "Nova conversa" do "Escrever" pedido pelo balão do menu recolhido (#1809):
// fica montada no ícone do menu e abre quando chega um pedido (escreverEmail.js), já
// com a caixa de e-mail escolhida.
import { nextTick, ref, useTemplateRef, watch } from 'vue';
import NovaConversaEntrada from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import { pedidoDeEscrever } from './escreverEmail';

const caixaId = ref(null);
const gatilho = useTemplateRef('gatilho');

watch(pedidoDeEscrever, async pedido => {
  if (!pedido) return;
  caixaId.value = pedido.caixaId;
  await nextTick();
  gatilho.value?.click();
});
</script>

<template>
  <NovaConversaEntrada :caixa-id="caixaId">
    <template #trigger>
      <button
        ref="gatilho"
        type="button"
        class="sr-only"
        tabindex="-1"
        aria-hidden="true"
      />
    </template>
  </NovaConversaEntrada>
</template>
