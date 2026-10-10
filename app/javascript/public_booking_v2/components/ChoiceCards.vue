<script setup>
// Escolha única em cartões grandes (local, duração). Rádios nativos escondidos: teclado (setas) e leitor de
// tela funcionam sem código extra. Nunca a lista nativa do navegador (regra do Rodrigo, 18/09/2026).
defineProps({
  name: { type: String, required: true },
  legend: { type: String, required: true },
  options: { type: Array, required: true },
});

const model = defineModel({ type: [String, Number], default: null });
</script>

<template>
  <fieldset class="flex flex-col gap-2">
    <legend class="mb-1 text-base font-semibold text-slate-900">
      {{ legend }}
    </legend>
    <label
      v-for="option in options"
      :key="option.value"
      class="flex min-h-14 cursor-pointer items-center gap-3 rounded-xl border-2 bg-white px-4 py-3 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-[var(--brand)] has-[:focus-visible]:ring-offset-2"
      :class="
        model === option.value
          ? 'border-[var(--brand)]'
          : 'border-slate-200 hover:border-slate-400'
      "
    >
      <input
        v-model="model"
        type="radio"
        class="sr-only"
        :name="name"
        :value="option.value"
      />
      <span
        aria-hidden="true"
        class="flex size-5 shrink-0 items-center justify-center rounded-full border-2"
        :class="
          model === option.value ? 'border-[var(--brand)]' : 'border-slate-400'
        "
      >
        <span
          v-if="model === option.value"
          class="size-2.5 rounded-full bg-[var(--brand)]"
        />
      </span>
      <span class="flex flex-col">
        <span class="text-base font-semibold text-slate-900">
          {{ option.label }}
        </span>
        <span v-if="option.hint" class="text-base text-slate-600">
          {{ option.hint }}
        </span>
      </span>
    </label>
  </fieldset>
</template>
