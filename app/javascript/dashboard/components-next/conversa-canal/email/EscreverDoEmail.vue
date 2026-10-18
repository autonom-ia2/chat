<script setup>
// Gaveta "Nova conversa" do "Escrever" pedido pelo balão do menu recolhido (#1809):
// fica montada no ícone do menu e abre quando chega um pedido (escreverEmail.js), já
// com a caixa de e-mail escolhida. A gaveta só monta depois do primeiro pedido: sem a
// chave conversa_email_nova (ou sem ninguém pedir), o ícone não carrega nada a mais.
import { nextTick, ref, useTemplateRef, watch } from 'vue';
import NovaConversaEntrada from 'dashboard/components-next/NovaConversa/NovaConversaEntrada.vue';
import { usePodeComecarConversa } from 'dashboard/components-next/NovaConversa/usePodeComecarConversa';
import { pedidoDeEscrever } from './escreverEmail';

const caixaId = ref(null);
const gatilho = useTemplateRef('gatilho');
// Quem só lê conversas (#1800) não abre a gaveta, nem por um pedido que sobrou.
const podeEscrever = usePodeComecarConversa();

watch(pedidoDeEscrever, async pedido => {
  if (!pedido || !podeEscrever.value) return;
  caixaId.value = pedido.caixaId;
  await nextTick();
  gatilho.value?.click();
});
</script>

<template>
  <NovaConversaEntrada v-if="caixaId" :caixa-id="caixaId">
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
  <template v-else />
</template>
