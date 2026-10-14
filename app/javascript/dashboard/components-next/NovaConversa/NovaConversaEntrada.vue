<script setup>
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import NovaConversaGaveta from './NovaConversaGaveta.vue';
import { useNovaConversaLigada } from './novaConversaLigada';

// #1459 — ponte entre a tela nova e a antiga. Os pontos de uso importam este
// componente no lugar do ComposeConversation; props, slot `trigger` e evento
// `close` passam direto, e a escolha entre as duas telas (a flag de conta
// `nova_conversa_tela`) fica num lugar só.
defineOptions({ inheritAttrs: false });

const ligada = useNovaConversaLigada();
</script>

<template>
  <component
    :is="ligada ? NovaConversaGaveta : ComposeConversation"
    v-bind="$attrs"
  >
    <template #trigger="escopo">
      <slot name="trigger" v-bind="escopo" />
    </template>
  </component>
</template>
