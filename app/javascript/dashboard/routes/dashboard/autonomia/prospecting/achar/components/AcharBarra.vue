<script setup>
// #2693 — a barra de quanto já foi (lista conferindo, fila "Para chamar"):
// um <progress> nativo pintado só com Tailwind, sem largura em estilo inline.
// Cada tom é uma string inteira de classes, para o Tailwind achar no código.
defineProps({
  valor: { type: Number, required: true },
  total: { type: Number, required: true },
  rotulo: { type: String, required: true },
  tom: { type: String, default: 'azul' },
});

const BASE =
  'block w-full overflow-hidden border-0 rounded-full appearance-none [&::-webkit-progress-bar]:rounded-full [&::-webkit-progress-value]:rounded-full [&::-webkit-progress-value]:transition-all [&::-moz-progress-bar]:rounded-full';
const TONS = {
  azul: 'h-2 bg-n-blue-4 [&::-webkit-progress-bar]:bg-n-blue-4 [&::-webkit-progress-value]:bg-n-blue-9 [&::-moz-progress-bar]:bg-n-blue-9',
  verde:
    'h-1 bg-n-slate-4 [&::-webkit-progress-bar]:bg-n-slate-4 [&::-webkit-progress-value]:bg-n-teal-9 [&::-moz-progress-bar]:bg-n-teal-9',
};
</script>

<template>
  <progress
    :value="valor"
    :max="Math.max(total, 1)"
    :aria-label="rotulo"
    :class="[BASE, TONS[tom] || TONS.azul]"
    data-barra
  />
</template>
