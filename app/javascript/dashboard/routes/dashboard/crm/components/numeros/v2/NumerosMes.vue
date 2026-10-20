<script setup>
import { P } from './numerosTextos';
import { useNumerosFormato } from './useNumerosFormato';

// Troca de mês (#1871): setas ‹ › com o nome do mês no aria-label e 44 px.
// Um relógio só: o mês é o da conta, no fuso dela.
defineProps({
  rotulo: { type: String, required: true },
  anterior: { type: String, default: '' },
  seguinte: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});
const emit = defineEmits(['anterior', 'seguinte']);

const { t } = useNumerosFormato();
</script>

<template>
  <nav
    :aria-label="t(`${P}.MES.NAV`)"
    data-numeros-mes
    class="inline-flex items-center gap-1 rounded-xl bg-n-alpha-2 p-1"
  >
    <button
      type="button"
      data-mes-anterior
      :disabled="disabled || !anterior"
      :aria-label="
        anterior ? t(`${P}.MES.ANTERIOR`, { mes: anterior }) : t(`${P}.MES.NAV`)
      "
      class="inline-flex size-11 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-solid-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-40"
      @click="emit('anterior')"
    >
      <span
        class="i-lucide-chevron-left size-5 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
    <span
      class="px-1 text-center text-sm font-semibold text-n-slate-12 first-letter:uppercase"
      aria-live="polite"
    >
      {{ rotulo }}
    </span>
    <button
      type="button"
      data-mes-seguinte
      :disabled="disabled || !seguinte"
      :aria-label="
        seguinte
          ? t(`${P}.MES.SEGUINTE`, { mes: seguinte })
          : t(`${P}.MES.SEM_SEGUINTE`)
      "
      class="inline-flex size-11 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-solid-1 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand disabled:opacity-40"
      @click="emit('seguinte')"
    >
      <span
        class="i-lucide-chevron-right size-5 rtl:rotate-180"
        aria-hidden="true"
      />
    </button>
  </nav>
</template>
