<script setup>
// #1423 — uma ficha curta de leitura: rótulo à esquerda, valor à direita.
defineProps({
  titulo: { type: String, default: '' },
  linhas: { type: Array, required: true },
});
</script>

<template>
  <section
    data-card-ficha
    class="flex flex-col rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm"
  >
    <h4 v-if="titulo" class="mb-2 text-base font-semibold text-n-slate-12">
      {{ titulo }}
    </h4>
    <dl class="m-0 flex flex-col divide-y divide-n-weak">
      <div
        v-for="linha in linhas"
        :key="linha.rotulo"
        class="flex flex-wrap items-baseline justify-between gap-x-4 gap-y-0.5 py-2.5"
      >
        <dt class="text-sm text-n-slate-11">{{ linha.rotulo }}</dt>
        <dd
          class="m-0 min-w-0 break-words text-end text-[0.9375rem] text-n-slate-12"
        >
          {{ linha.valor }}
        </dd>
      </div>
    </dl>
    <slot />
  </section>
</template>
