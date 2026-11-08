<script setup>
import BotaoGrande from './BotaoGrande.vue';

// Uma pergunta da conversa guiada (#2308, especificação 5.B3): título-pergunta, dica, conteúdo e "Pronto", que volta
// a Ajustes.
defineProps({
  titulo: { type: String, required: true },
  dica: { type: String, default: '' },
});

const emit = defineEmits(['pronto']);
</script>

<template>
  <div class="flex flex-col gap-5">
    <header class="flex flex-col gap-2">
      <h1
        class="m-0 text-2xl font-bold tracking-tight sm:text-3xl text-n-slate-12"
      >
        {{ titulo }}
      </h1>
      <slot name="dica">
        <p v-if="dica" class="m-0 text-base text-n-slate-11">{{ dica }}</p>
      </slot>
    </header>
    <slot />
    <BotaoGrande
      :label="$t('FUNCOES_EQUIPE.GUIADA.PRONTO')"
      @click="emit('pronto')"
    />
  </div>
</template>
