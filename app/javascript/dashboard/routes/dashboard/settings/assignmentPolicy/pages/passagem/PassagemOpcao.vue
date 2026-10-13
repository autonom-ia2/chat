<script setup>
// Cartão de escolha única com <input type="radio"> de verdade: setas, Tab e leitor de tela vêm do navegador.
// Desenho do funil (#1384): o escolhido ganha o visto azul à esquerda e a borda azul.
defineProps({
  name: { type: String, required: true },
  value: { type: String, required: true },
  titulo: { type: String, required: true },
  descricao: { type: String, default: '' },
  icone: { type: String, default: '' },
});

const escolhido = defineModel({ type: String, required: true });
</script>

<template>
  <label
    class="relative flex min-h-11 cursor-pointer gap-3 rounded-2xl border bg-n-solid-1 p-4 transition-colors has-[:focus-visible]:outline has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2 has-[:focus-visible]:outline-n-brand"
    :class="
      escolhido === value
        ? 'border-n-blue-8 bg-n-blue-2 shadow-sm'
        : 'border-n-weak hover:border-n-slate-7'
    "
  >
    <input
      v-model="escolhido"
      type="radio"
      class="sr-only"
      :name="name"
      :value="value"
    />
    <span
      class="mt-0.5 grid size-5 shrink-0 place-items-center rounded-full"
      :class="
        escolhido === value
          ? 'bg-n-blue-9 text-white'
          : 'ring-2 ring-inset ring-n-slate-7'
      "
      aria-hidden="true"
    >
      <span v-if="escolhido === value" class="i-lucide-check size-3.5" />
    </span>
    <span class="flex min-w-0 flex-1 flex-col gap-1">
      <span
        class="flex items-center gap-2 text-[0.9375rem] font-semibold text-n-slate-12"
      >
        <span
          v-if="icone"
          :class="icone"
          class="size-4 text-n-slate-11"
          aria-hidden="true"
        />
        {{ titulo }}
      </span>
      <span v-if="descricao" class="text-sm leading-5 text-n-slate-11">{{
        descricao
      }}</span>
    </span>
  </label>
</template>
