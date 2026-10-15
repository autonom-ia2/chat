<script setup>
import Button from 'dashboard/components-next/button/Button.vue';

// #1487 — uma parte de uma configuração em uma frase: ícone, nome pequeno, a frase e "Alterar". Mesma anatomia do
// cartão-resumo do funil (#1384, FunilResumoCartao), sem depender do CRM: os textos do botão vêm de quem usa.
// `apagado`: a parte não vale agora (ex.: um interruptor acima está desligado) — o cartão esmaece e não oferece
// "Alterar"; a frase explica o porquê. O slot `acao` troca o botão (ex.: um interruptor no cabeçalho).
defineProps({
  name: { type: String, required: true },
  icon: { type: String, required: true },
  tone: { type: String, default: 'bg-n-blue-3 text-n-blue-11' },
  title: { type: String, required: true },
  editLabel: { type: String, default: '' },
  editAriaLabel: { type: String, default: '' },
  dimmed: { type: Boolean, default: false },
});

defineEmits(['edit']);
</script>

<template>
  <article
    :data-summary-card="name"
    :aria-disabled="dimmed || undefined"
    class="flex items-start gap-3 p-4 transition border shadow-sm rounded-2xl bg-n-solid-1 sm:gap-4 sm:p-5"
    :class="
      dimmed
        ? 'border-n-weak opacity-60'
        : 'border-n-weak hover:border-n-slate-7 focus-within:border-n-blue-8 focus-within:shadow-md'
    "
  >
    <span
      class="grid size-10 shrink-0 place-items-center rounded-2xl sm:size-12"
      :class="dimmed ? 'bg-n-alpha-2 text-n-slate-10' : tone"
      aria-hidden="true"
    >
      <span class="size-5 sm:size-6" :class="icon" />
    </span>
    <div class="flex flex-col flex-1 min-w-0 gap-1">
      <div class="flex items-center gap-3 min-h-11">
        <h3 class="flex-1 min-w-0 mb-0 text-sm font-medium text-n-slate-11">
          {{ title }}
        </h3>
        <slot name="acao">
          <Button
            v-if="editLabel && !dimmed"
            :label="editLabel"
            :aria-label="editAriaLabel || undefined"
            icon="i-lucide-pencil"
            slate
            faded
            class="!min-h-11 shrink-0"
            @click="$emit('edit')"
          />
        </slot>
      </div>
      <div class="-mt-2 text-base leading-relaxed text-n-slate-12">
        <slot />
      </div>
      <slot name="extra" />
    </div>
  </article>
</template>
