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
  <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
    <legend class="mb-1 p-0 text-base font-semibold text-bk-strong">
      {{ legend }}
    </legend>
    <label
      v-for="option in options"
      :key="option.value"
      class="flex min-h-14 cursor-pointer items-center gap-3 rounded-xl border-2 border-solid bg-bk-field px-4 py-3 has-[:focus-visible]:ring-2 has-[:focus-visible]:ring-[var(--brand)] has-[:focus-visible]:ring-offset-2 has-[:focus-visible]:ring-offset-bk-card"
      :class="
        model === option.value
          ? 'border-[var(--brand)]'
          : 'border-bk-line hover:border-bk-line-hover'
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
        class="flex size-5 shrink-0 items-center justify-center rounded-full border-2 border-solid"
        :class="
          model === option.value
            ? 'border-[var(--brand)]'
            : 'border-bk-line-hover'
        "
      >
        <span
          v-if="model === option.value"
          class="size-2.5 rounded-full bg-[var(--brand)]"
        />
      </span>
      <span class="flex flex-col">
        <span class="text-base font-semibold text-bk-strong">
          {{ option.label }}
        </span>
        <span v-if="option.hint" class="text-base text-bk-soft">
          {{ option.hint }}
        </span>
      </span>
    </label>
  </fieldset>
</template>
