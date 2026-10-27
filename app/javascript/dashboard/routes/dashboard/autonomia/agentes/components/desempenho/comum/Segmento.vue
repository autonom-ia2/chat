<script setup>
// #2226 v2 — escolha em segmento (abas, período, visão do gráfico, corte). Faz o papel do TabBar do
// components-next, mas com alvo de toque de 44px, que o TabBar (32px) não tem. A opção escolhida
// fica clara e com sombra, como na referência.
defineProps({
  // [{ value, label }]
  opcoes: { type: Array, required: true },
  rotulo: { type: String, required: true },
});

const escolhida = defineModel({ type: String, required: true });
</script>

<template>
  <div
    role="group"
    :aria-label="rotulo"
    data-segmento
    class="inline-flex flex-wrap items-center gap-0.5 p-0.5 rounded-xl bg-n-alpha-1 dark:bg-n-alpha-2 ring-1 ring-n-weak dark:ring-n-slate-6 w-fit max-w-full"
  >
    <button
      v-for="opcao in opcoes"
      :key="opcao.value"
      type="button"
      :data-opcao="opcao.value"
      :aria-pressed="escolhida === opcao.value"
      class="px-3 text-sm whitespace-nowrap transition-colors rounded-lg min-h-11 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
      :class="
        escolhida === opcao.value
          ? 'bg-n-solid-1 dark:bg-n-solid-3 shadow-sm font-semibold text-n-slate-12 dark:ring-1 dark:ring-n-slate-7'
          : 'text-n-slate-11 hover:text-n-slate-12'
      "
      @click="escolhida = opcao.value"
    >
      {{ opcao.label }}
    </button>
  </div>
</template>
