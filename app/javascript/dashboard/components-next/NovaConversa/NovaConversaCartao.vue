<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1459 — uma escolha já feita, em uma frase: ícone, nome pequeno, a frase
// com o dado em negrito e "Alterar" cinza. Mesmo desenho do cartão-resumo do
// funil (#1384).
defineProps({
  icone: { type: String, required: true },
  tom: { type: String, default: 'bg-n-blue-3 text-n-blue-11' },
  titulo: { type: String, required: true },
  semAlterar: { type: Boolean, default: false },
});

defineEmits(['alterar']);
</script>

<template>
  <article
    class="flex items-center gap-3 rounded-2xl border border-n-weak bg-n-solid-1 p-4 shadow-sm sm:gap-4"
  >
    <span
      class="grid size-11 shrink-0 place-items-center rounded-2xl"
      :class="tom"
      aria-hidden="true"
    >
      <span class="size-5" :class="icone" />
    </span>
    <div class="flex min-w-0 flex-1 flex-col gap-0.5">
      <h3 class="mb-0 text-sm font-medium text-n-slate-11">{{ titulo }}</h3>
      <p class="mb-0 break-words text-base leading-relaxed text-n-slate-12">
        <slot />
      </p>
    </div>
    <Button
      v-if="!semAlterar"
      :label="$t('NOVA_CONVERSA.ALTERAR')"
      :aria-label="$t('NOVA_CONVERSA.ALTERAR_PARTE', { parte: titulo })"
      icon="i-lucide-pencil"
      slate
      faded
      class="!min-h-11 shrink-0"
      @click="$emit('alterar')"
    />
  </article>
</template>
