<script setup>
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NovaConversaGaveta from './NovaConversaGaveta.vue';
import { useNovaConversaLigada } from './novaConversaLigada';
import { usePodeComecarConversa } from './usePodeComecarConversa';

// #1459 — ponte entre a tela nova e a antiga. Os pontos de uso importam este
// componente no lugar do ComposeConversation; props, slot `trigger` e evento
// `close` passam direto, e a escolha entre as duas telas (a flag de conta
// `nova_conversa_tela`) fica num lugar só.
defineOptions({ inheritAttrs: false });

const ligada = useNovaConversaLigada();

// Quem só lê conversas (#1800) não começa conversa nova, em nenhum ponto de entrada.
const podeComecar = usePodeComecarConversa();
</script>

<template>
  <component
    :is="ligada ? NovaConversaGaveta : ComposeConversation"
    v-if="podeComecar"
    v-bind="$attrs"
  >
    <template #trigger="escopo">
      <slot name="trigger" v-bind="escopo" />
    </template>
  </component>
  <template v-else />
</template>
