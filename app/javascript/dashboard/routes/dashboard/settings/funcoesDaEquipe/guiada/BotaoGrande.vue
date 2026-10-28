<script setup>
// O botão principal de cada etapa (#2308, especificação 4 e 10): 52 px logo depois do conteúdo no computador; no
// celular, fixo embaixo, com sombra para cima e o esmaecido de 56 px. A página reserva o padding de baixo. "Celular"
// é abaixo de md (768 px), o mesmo ponto em que a barra lateral vira o botão flutuante do menu
// (MobileSidebarLauncher, fixo em bottom-4 start-4): o rodapé reserva o espaço dele à esquerda.
defineProps({
  label: { type: String, required: true },
  carregando: { type: Boolean, default: false },
});

const emit = defineEmits(['click']);
</script>

<template>
  <div
    class="max-md:fixed max-md:inset-x-0 max-md:bottom-0 max-md:z-10 max-md:py-4 max-md:pe-4 max-md:ps-20 max-md:border-t max-md:border-n-weak max-md:bg-n-solid-1 max-md:shadow-[0_-8px_16px_-8px_rgb(0_0_0/0.12)]"
  >
    <span
      aria-hidden="true"
      class="absolute inset-x-0 pointer-events-none md:hidden -top-14 h-14 bg-gradient-to-t from-n-surface-1 to-transparent"
    />
    <slot name="acima" />
    <button
      type="button"
      data-botao-grande
      class="flex items-center justify-center w-full gap-2 px-6 text-base font-semibold text-white transition-colors h-[3.25rem] rounded-xl bg-n-brand hover:enabled:bg-n-blue-10 disabled:bg-n-alpha-2 disabled:text-n-slate-10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
      :disabled="carregando"
      :aria-busy="carregando"
      @click="emit('click')"
    >
      <span
        v-if="carregando"
        class="i-lucide-loader-circle size-5 animate-spin"
        aria-hidden="true"
      />
      {{ label }}
    </button>
  </div>
</template>
