<script setup>
// #1487 — moldura da prévia ao lado de uma escolha: selo, título e uma frase. Mesma anatomia da PreviaMoldura do
// funil (#1384), sem o CRM: o texto do selo vem de quem usa ("Prévia" para o que vai mudar, "Agora" para o que é).
defineProps({
  badge: { type: String, required: true },
  title: { type: String, required: true },
  text: { type: String, default: '' },
});
</script>

<template>
  <section data-preview-frame class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <span class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2 py-0.5 text-xs font-semibold text-n-teal-11"
        >
          <span class="size-1.5 rounded-full bg-n-teal-9" aria-hidden="true" />
          {{ badge }}
        </span>
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ title }}
        </h3>
      </span>
      <p v-if="text" class="mb-0 text-sm text-n-slate-11">{{ text }}</p>
    </header>
    <slot />
  </section>
</template>
