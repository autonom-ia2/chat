<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #2692 — T2 e T3, as telas de pronto (molde visual
// CampaignJourney/AudienceSearchSaved.vue, que tem o i18n de Campanhas fixo):
// círculo verde-água com visto, título, detalhe, um botão principal e um link.
// Rodada 4: nas páginas, o botão principal vai para o rodapé fixo (AcharRodape)
// e o cartão fica com o texto e o link; `principal` vazio não desenha botão.
defineProps({
  titulo: { type: String, required: true },
  detalhes: { type: Array, default: () => [] },
  principal: { type: String, default: '' },
  link: { type: String, default: '' },
});
const emit = defineEmits(['principal', 'link']);
</script>

<template>
  <section
    class="flex flex-col items-center gap-4 px-5 py-10 text-center border shadow-sm rounded-3xl border-n-weak bg-n-solid-1 md:px-10"
    data-pronto
  >
    <span
      class="grid rounded-full size-20 place-items-center bg-n-teal-3 text-n-teal-11"
      aria-hidden="true"
    >
      <span class="i-lucide-check size-10" />
    </span>
    <h2
      class="max-w-xl m-0 text-2xl font-bold text-n-slate-12 md:text-[2rem] md:leading-tight"
    >
      {{ titulo }}
    </h2>
    <p
      v-for="detalhe in detalhes"
      :key="detalhe"
      class="m-0 text-base text-n-slate-11"
    >
      {{ detalhe }}
    </p>
    <div
      v-if="principal || link"
      class="flex flex-col w-full gap-2 mt-2 sm:w-auto"
    >
      <Button
        v-if="principal"
        :label="principal"
        class="!h-auto !min-h-12 !whitespace-normal !rounded-xl !px-6 !py-2 !text-base"
        data-principal-pronto
        @click="emit('principal')"
      />
      <Button
        v-if="link"
        :label="link"
        variant="link"
        class="!min-h-11 justify-center"
        data-link-pronto
        @click="emit('link')"
      />
    </div>
  </section>
</template>
