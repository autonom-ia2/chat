<script setup>
import { computed } from 'vue';

// Botão grande (alvo de 48 px, texto de 16 px). Com `href` vira link: quem chama passa só URL já conferida
// por helpers/url.js.
const props = defineProps({
  variant: {
    type: String,
    default: 'primary',
    validator: value => ['primary', 'secondary', 'ghost'].includes(value),
  },
  href: { type: String, default: '' },
  type: { type: String, default: 'button' },
  disabled: { type: Boolean, default: false },
  download: { type: Boolean, default: false },
  external: { type: Boolean, default: false },
});

const VARIANTS = {
  primary: 'bg-[var(--brand)] text-white shadow-sm hover:brightness-110',
  secondary:
    'border-2 border-[var(--brand)] bg-white text-[var(--brand)] hover:bg-slate-50',
  ghost:
    'bg-transparent text-[var(--brand)] underline-offset-4 hover:underline',
};

const classes = computed(() => [
  'inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-xl px-5 py-3 text-center text-base font-semibold transition',
  'focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[var(--brand)]',
  'disabled:cursor-not-allowed disabled:opacity-60',
  VARIANTS[props.variant],
]);
</script>

<template>
  <a
    v-if="href"
    :href="href"
    :class="classes"
    :download="download ? '' : undefined"
    :target="external ? '_blank' : undefined"
    :rel="external ? 'noopener noreferrer' : undefined"
  >
    <slot />
  </a>
  <button v-else :type="type" :class="classes" :disabled="disabled">
    <slot />
  </button>
</template>
