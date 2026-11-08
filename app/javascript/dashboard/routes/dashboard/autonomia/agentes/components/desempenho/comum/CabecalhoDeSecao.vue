<script setup>
// #2226 v2 — o cabeçalho de cada seção do Resumo: uma linha pequena que diz o assunto (sem caixa
// alta), o título e uma descrição curta. A hierarquia vem do peso e da cor, não do tamanho.
defineProps({
  id: { type: String, required: true },
  sobre: { type: String, default: '' },
  titulo: { type: String, required: true },
  descricao: { type: String, default: '' },
});
</script>

<template>
  <header class="flex flex-wrap items-end justify-between gap-x-6 gap-y-2">
    <div class="flex flex-col gap-1">
      <p v-if="sobre" class="m-0 text-xs font-semibold text-n-blue-11">
        {{ sobre }}
      </p>
      <h2 :id="id" class="m-0 text-lg font-semibold text-n-slate-12">
        {{ titulo }}
      </h2>
      <p v-if="descricao" class="max-w-3xl m-0 text-xs text-n-slate-11">
        {{ descricao }}
      </p>
    </div>
    <slot />
  </header>
</template>
