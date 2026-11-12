<script setup>
// #2894 — selo pequeno ao lado do nome: "Cliente" (verde, mesmo visual do
// CustomerBadge), "Não quer mensagens" (âmbar) ou um aviso neutro. O texto vem
// de quem usa o selo; o selo nunca encolhe (quem corta é o nome ao lado).
defineProps({
  tom: {
    type: String,
    default: 'neutro',
    validator: valor => ['cliente', 'alerta', 'neutro'].includes(valor),
  },
});

const ESTILOS = {
  cliente: 'bg-n-teal-3 text-n-teal-11',
  alerta: 'bg-n-amber-3 text-n-amber-11',
  neutro: 'bg-n-alpha-2 text-n-slate-11',
};
const ICONES = {
  cliente: 'i-lucide-badge-check',
  alerta: 'i-lucide-bell-off',
  neutro: '',
};
</script>

<template>
  <span
    :data-selo="tom"
    class="inline-flex items-center gap-1 px-1.5 text-xs font-medium leading-5 normal-case align-middle rounded-md shrink-0 whitespace-nowrap"
    :class="ESTILOS[tom]"
  >
    <span
      v-if="ICONES[tom]"
      class="size-3.5 shrink-0"
      :class="ICONES[tom]"
      aria-hidden="true"
    />
    <slot />
  </span>
</template>
