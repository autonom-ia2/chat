<script setup>
// #1423 — moldura da coluna da direita, na família da PreviaMoldura (#1384):
// selo, título e uma frase. "Prévia" mostra o que vai mudar; "Agora", o
// estado de agora. Lista de consulta (o primeiro da fila, quando chegou) vai
// sem selo, para "Agora" não querer dizer outra coisa.
defineProps({
  titulo: { type: String, required: true },
  texto: { type: String, default: '' },
  selo: {
    type: String,
    default: 'agora',
    validator: valor => ['previa', 'agora', ''].includes(valor),
  },
});
</script>

<template>
  <section data-funil-previa :data-selo="selo" class="flex flex-col gap-4">
    <header class="flex flex-col gap-1">
      <span class="flex flex-wrap items-center gap-2">
        <span
          v-if="selo"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-teal-3 px-2 py-0.5 text-xs font-semibold text-n-teal-11"
        >
          <span class="size-1.5 rounded-full bg-n-teal-9" aria-hidden="true" />
          {{
            $t(
              selo === 'agora'
                ? 'CRM_FUNIL.PREVIA.SELO_AGORA'
                : 'CRM_FUNIL.PREVIA.SELO'
            )
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
