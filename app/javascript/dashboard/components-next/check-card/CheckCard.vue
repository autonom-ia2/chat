<script setup>
// #1487 — cartão marcável (vários podem ficar marcados) com <input type="checkbox"> de verdade: Tab, espaço e
// leitor de tela vêm do navegador. Mesma anatomia das opções da passagem (#1385, PassagemOpcao) e da Nova conversa
// (#1459): o marcado ganha o visto azul e a borda azul. O slot `selos` traz selos (recomendado, aviso).
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  icon: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const checked = defineModel({ type: Boolean, default: false });
</script>

<template>
  <label
    class="relative flex gap-3 p-4 transition-colors border cursor-pointer min-h-11 rounded-2xl bg-n-solid-1 has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-n-brand"
    :class="[
      checked
        ? 'border-n-blue-8 bg-n-blue-2 shadow-sm'
        : 'border-n-weak hover:border-n-slate-7',
      disabled && 'cursor-not-allowed opacity-60',
    ]"
  >
    <input
      v-model="checked"
      type="checkbox"
      class="sr-only"
      :disabled="disabled"
    />
    <span
      class="mt-0.5 grid size-5 shrink-0 place-items-center rounded-md"
      :class="
        checked ? 'bg-n-blue-9 text-white' : 'ring-2 ring-inset ring-n-slate-7'
      "
      aria-hidden="true"
    >
      <span v-if="checked" class="i-lucide-check size-3.5" />
    </span>
    <span class="flex flex-col flex-1 min-w-0 gap-1">
      <span
        class="flex items-start gap-2 text-[0.9375rem] font-semibold text-n-slate-12"
      >
        <span
          v-if="icon"
          :class="icon"
          class="size-4 mt-0.5 shrink-0 text-n-slate-11"
          aria-hidden="true"
        />
        <span class="min-w-0 break-words">{{ title }}</span>
      </span>
      <span v-if="description" class="text-sm leading-5 text-n-slate-11">
        {{ description }}
      </span>
      <span v-if="$slots.selos" class="flex flex-wrap gap-1.5 mt-1">
        <slot name="selos" />
      </span>
    </span>
  </label>
</template>
