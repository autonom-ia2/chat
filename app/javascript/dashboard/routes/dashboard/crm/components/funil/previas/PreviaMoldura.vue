<script setup>
// #1384 — moldura da coluna da direita: selo, título e uma frase. O selo diz
// "Prévia" quando mostra o que vai mudar e "Agora" quando mostra o que já é.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  agora: { type: Boolean, default: false },
});
</script>

<template>
  <section data-funil-previa class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <span class="flex flex-wrap items-center gap-2">
        <span
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2 py-0.5 text-xs font-semibold text-n-teal-11"
        >
          <span class="size-1.5 rounded-full bg-n-teal-9" aria-hidden="true" />
          {{
            $t(agora ? 'CRM_FUNIL.PREVIA.SELO_AGORA' : 'CRM_FUNIL.PREVIA.SELO')
          }}
        </span>
        <h3 class="mb-0 text-base font-semibold text-n-slate-12">
          {{ titulo }}
        </h3>
      </span>
      <p v-if="texto" class="mb-0 text-sm text-n-slate-11">{{ texto }}</p>
    </header>
    <slot />
  </section>
</template>
