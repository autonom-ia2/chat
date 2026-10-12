<script setup>
// #1384 — a frase da coluna acesa. Com a sugestão aberta, mostra como fica
// se a pessoa usar a sugestão; sem frase, o aviso âmbar.
defineProps({
  nome: { type: String, default: '' },
  cor: { type: String, default: '' },
  frase: { type: String, default: '' },
  sugestao: { type: String, default: '' },
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4"
  >
    <span
      class="inline-flex w-fit items-center gap-2 rounded-lg bg-n-alpha-2 px-2.5 py-1 text-sm font-medium text-n-slate-12"
    >
      <span
        class="size-2.5 rounded-full"
        :style="{ backgroundColor: cor }"
        aria-hidden="true"
      />
      {{ nome || '…' }}
    </span>
    <template v-if="sugestao.trim()">
      <p class="mb-0 text-sm font-medium text-n-blue-11">
        {{ $t('CRM_FUNIL.PREVIA.ETAPA_SE_USAR') }}
      </p>
      <blockquote
        class="m-0 border-s-4 border-n-blue-8 ps-3 text-[0.9375rem] leading-relaxed text-n-slate-12"
      >
        {{ sugestao }}
      </blockquote>
    </template>
    <blockquote
      v-else-if="frase.trim()"
      class="m-0 border-s-4 border-n-slate-6 ps-3 text-[0.9375rem] leading-relaxed text-n-slate-12"
    >
      {{ frase }}
    </blockquote>
    <p
      v-else
      class="mb-0 rounded-xl border border-dashed border-n-amber-8 bg-n-amber-2 p-3 text-sm text-n-slate-12"
    >
      {{ $t('CRM_FUNIL.PREVIA.ETAPA_FALTA') }}
    </p>
  </section>
</template>
