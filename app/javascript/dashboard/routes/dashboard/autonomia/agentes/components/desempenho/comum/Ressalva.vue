<script setup>
// #2226 v2 — a ressalva fica colada ao número de que fala, nunca escondida. A 1ª frase vai em
// negrito; o resto, normal.
defineProps({
  destaque: { type: String, default: '' },
  texto: { type: String, default: '' },
});
</script>

<template>
  <p
    data-ressalva
    class="flex items-start gap-2 px-4 py-3 m-0 text-xs rounded-xl bg-n-amber-2 ring-1 ring-n-amber-5 text-n-slate-12"
  >
    <span
      class="i-lucide-info size-4 shrink-0 text-n-amber-11"
      aria-hidden="true"
    />
    <span>
      <strong v-if="destaque" class="font-semibold">{{ destaque }}</strong>
      {{ texto }}
      <slot />
    </span>
  </p>
</template>
