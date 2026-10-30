<script setup>
// Balão de texto do Direct (#2079): 15 px, 8×12 de respiro, cantos do grupo. O texto
// passa pelo mesmo formatador do balão de sempre (link clicável, sem HTML do cliente).
import { computed } from 'vue';
import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { BALAO_DE_TEXTO, ENVIADO, RECEBIDO } from './visualInstagram';

const props = defineProps({
  texto: { type: String, required: true },
  enviada: { type: Boolean, default: false },
  cantos: { type: Object, required: true },
});

const cor = computed(() => (props.enviada ? ENVIADO : RECEBIDO));
const formatado = computed(
  () => new MessageFormatter(props.texto).formattedMessage
);
</script>

<template>
  <div
    v-dompurify-html="formatado"
    class="!whitespace-normal [&_p]:m-0 [&_:is(p,li)]:!text-[15px] [&_:is(p,li)]:!leading-5 [&>*+*]:!mt-2 [&_ol]:!list-decimal [&_ol]:ps-5 [&_ul]:ps-5 [&_a]:underline [&_a]:!text-[inherit]"
    :class="[BALAO_DE_TEXTO, cor]"
    :style="cantos"
    dir="auto"
  />
</template>
