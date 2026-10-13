<script setup>
// Um botão como o cliente o vê. Com `href` o atendente abre o endereço em outra aba; sem ele é só a imagem do botão.
import Icon from 'next/icon/Icon.vue';

defineProps({
  label: { type: String, required: true },
  icon: { type: String, default: '' },
  href: { type: String, default: '' },
});
</script>

<template>
  <a
    v-if="href"
    :href="href"
    target="_blank"
    rel="noopener noreferrer"
    class="flex items-center justify-center gap-2 w-full min-h-11 bg-n-solid-3 px-4 py-2 rounded-lg text-sm text-center text-n-slate-12 border border-n-container hover:bg-n-alpha-2"
  >
    <Icon v-if="icon" :icon="icon" class="size-4 flex-shrink-0" />
    <span class="min-w-0 break-words">{{ label }}</span>
  </a>
  <div
    v-else
    class="flex items-center justify-center gap-2 w-full min-h-9 bg-n-solid-3 px-4 py-2 rounded-lg text-sm text-center text-n-slate-12 border border-n-container"
  >
    <Icon v-if="icon" :icon="icon" class="size-4 flex-shrink-0" />
    <span class="min-w-0 break-words">{{ label }}</span>
  </div>
</template>
