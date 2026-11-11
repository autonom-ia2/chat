<script setup>
// #2894 — selo pequeno ao lado do nome: "Cliente" (verde, mesmo visual do
// CustomerBadge), "Não quer mensagens" (âmbar) ou um aviso neutro. O texto vem
// de quem usa o selo; o selo nunca encolhe (quem corta é o nome ao lado).
// #2897 — tons só de cor, para os selos da carteira: verde, verde com ✓, azul,
// vermelho, âmbar, cinza e cinza azulado.
defineProps({
  tom: {
    type: String,
    default: 'neutro',
    validator: valor =>
      [
        'cliente',
        'alerta',
        'neutro',
        'verde',
        'verde_ok',
        'azul',
        'vermelho',
        'ambar',
        'cinza',
        'azulado',
      ].includes(valor),
  },
});

const ESTILOS = {
  cliente: 'bg-n-teal-3 text-n-teal-11',
  alerta: 'bg-n-amber-3 text-n-amber-11',
  neutro: 'bg-n-alpha-2 text-n-slate-11',
  verde: 'bg-n-teal-3 text-n-teal-11',
  verde_ok: 'bg-n-teal-3 text-n-teal-11',
  azul: 'bg-n-blue-3 text-n-blue-11',
  vermelho: 'bg-n-ruby-3 text-n-ruby-11',
  ambar: 'bg-n-amber-3 text-n-amber-11',
  cinza: 'bg-n-alpha-2 text-n-slate-11',
  azulado: 'bg-n-slate-4 text-n-blue-11',
};
const ICONES = {
  cliente: 'i-lucide-badge-check',
  alerta: 'i-lucide-bell-off',
  verde_ok: 'i-lucide-check',
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
