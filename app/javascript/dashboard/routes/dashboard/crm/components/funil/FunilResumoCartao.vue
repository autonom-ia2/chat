<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1384 — uma parte do funil em uma frase, no padrão do CaixaCartao: ícone,
// nome pequeno, a frase com o dado em negrito e "Alterar" cinza. O ícone tem
// a cor da parte e o cartão em foco ganha a borda azul. Âmbar só para o que
// falta.
defineProps({
  parte: { type: String, required: true },
  icone: { type: String, required: true },
  tom: { type: String, default: 'bg-n-blue-3 text-n-blue-11' },
  titulo: { type: String, required: true },
  falta: { type: Boolean, default: false },
  semAlterar: { type: Boolean, default: false },
});

defineEmits(['alterar']);
</script>

<template>
  <article
    :data-setting="parte"
    class="flex items-start gap-3 rounded-2xl border bg-n-solid-1 p-4 shadow-sm transition sm:gap-4 sm:p-5"
    :class="
      falta
        ? 'border-n-amber-7'
        : 'border-n-weak hover:border-n-slate-7 focus-within:border-n-blue-8 focus-within:shadow-md'
    "
  >
    <span
      class="grid size-10 shrink-0 place-items-center rounded-2xl sm:size-12"
      :class="falta ? 'bg-n-amber-3 text-n-amber-11' : tom"
      aria-hidden="true"
    >
      <span class="size-5 sm:size-6" :class="icone" />
    </span>
    <div class="flex min-w-0 flex-1 flex-col gap-1">
      <div class="flex min-h-11 items-center gap-3">
        <h3 class="mb-0 min-w-0 flex-1 text-sm font-medium text-n-slate-11">
          {{ titulo }}
        </h3>
        <Button
          v-if="!semAlterar"
          :label="$t('CRM_FUNIL.ALTERAR')"
          :aria-label="$t('CRM_FUNIL.ALTERAR_PARTE', { parte: titulo })"
          icon="i-lucide-pencil"
          slate
          faded
          class="!min-h-11 shrink-0"
          @click="$emit('alterar')"
        />
      </div>
      <p class="-mt-2 mb-0 text-base leading-relaxed text-n-slate-12">
        <slot />
      </p>
      <slot name="extra" />
    </div>
  </article>
</template>
