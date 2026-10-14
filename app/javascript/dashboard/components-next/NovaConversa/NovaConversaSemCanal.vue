<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1459 — contato sem telefone nem e-mail: a tela inteira vira um estado
// vazio, com uma frase e a única ação azul, "Completar o cadastro".
defineProps({
  nome: { type: String, default: '' },
});

defineEmits(['completar']);

const P = 'NOVA_CONVERSA.POR_ONDE';
</script>

<template>
  <div
    data-nova-conversa-sem-canal
    class="mx-auto flex w-full max-w-md flex-col items-center gap-4 rounded-2xl border border-n-weak bg-n-solid-1 px-6 py-10 text-center shadow-sm"
  >
    <span
      class="grid size-16 place-items-center rounded-full bg-n-amber-3 text-n-amber-11"
      aria-hidden="true"
    >
      <span class="i-lucide-contact-round size-8" />
    </span>
    <p class="mb-0 text-base leading-relaxed text-n-slate-12">
      {{ nome ? $t(`${P}.VAZIO`, { nome }) : $t(`${P}.VAZIO_SEM_NOME`) }}
    </p>
    <Button
      data-nova-conversa-principal
      data-foco
      :label="$t(`${P}.COMPLETAR`)"
      icon="i-lucide-pencil"
      class="!min-h-11"
      @click="$emit('completar')"
    />
  </div>
</template>
