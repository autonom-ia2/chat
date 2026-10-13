<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import { seloDaCor } from './funil';

// #1384 — uma etapa na lista: número na cor da coluna e, ao lado, o nome com
// a frase em até duas linhas (a inteira fica em "Alterar"). Sem frase, a borda
// fica âmbar, a linha diz o que falta e há um único botão para sugerir.
defineProps({
  nome: { type: String, required: true },
  cor: { type: String, required: true },
  numero: { type: Number, required: true },
  frase: { type: String, default: '' },
  // Pode pedir a frase pronta (CRM com IA e permissão).
  ia: { type: Boolean, default: false },
});

defineEmits(['alterar', 'criar']);
</script>

<template>
  <article
    data-stage-row
    class="flex min-w-0 flex-col gap-2 rounded-2xl border bg-n-solid-1 p-3 transition hover:border-n-slate-7 focus-within:border-n-blue-8 sm:p-4"
    :class="!frase.trim() && ia ? 'border-n-amber-7' : 'border-n-weak'"
  >
    <div class="flex min-w-0 items-start gap-3">
      <slot name="alca" />
      <span
        class="grid size-10 shrink-0 place-items-center rounded-xl text-base font-bold"
        :class="seloDaCor(cor)"
        aria-hidden="true"
      >
        {{ numero }}
      </span>
      <div class="flex min-w-0 flex-1 flex-col gap-0.5 pt-0.5">
        <h4 class="mb-0 break-words text-base font-semibold text-n-slate-12">
          {{ nome }}
        </h4>
        <p
          v-if="frase.trim()"
          :title="frase"
          class="mb-0 line-clamp-2 text-sm leading-relaxed text-n-slate-11"
        >
          {{ frase }}
        </p>
        <p
          v-else-if="ia"
          data-etapa-falta
          class="mb-0 flex items-center gap-1.5 text-sm text-n-amber-11"
        >
          <span
            class="i-lucide-triangle-alert size-4 shrink-0"
            aria-hidden="true"
          />
          {{ $t('CRM_FUNIL.ETAPAS.FALTA') }}
        </p>
      </div>
      <!-- No celular, "Alterar" vira só o lápis (com nome para leitor de
           tela) para a frase ganhar espaço. -->
      <Button
        :data-stage-open="nome"
        :label="$t('CRM_FUNIL.ALTERAR')"
        :aria-label="$t('CRM_FUNIL.ETAPAS.ALTERAR_ETAPA', { nome })"
        icon="i-lucide-pencil"
        slate
        faded
        class="!hidden !min-h-11 shrink-0 sm:!inline-flex"
        @click="$emit('alterar')"
      />
      <Button
        :data-stage-open="nome"
        :aria-label="$t('CRM_FUNIL.ETAPAS.ALTERAR_ETAPA', { nome })"
        :title="$t('CRM_FUNIL.ALTERAR')"
        icon="i-lucide-pencil"
        slate
        faded
        class="!min-h-11 !min-w-11 shrink-0 sm:!hidden"
        @click="$emit('alterar')"
      />
    </div>
    <div
      v-if="!frase.trim() && ia"
      class="flex"
      :class="$slots.alca ? 'sm:ps-[6.25rem]' : 'sm:ps-[3.25rem]'"
    >
      <Button
        :label="$t('CRM_FUNIL.ETAPAS.CRIAR_IA')"
        icon="i-lucide-sparkles"
        amber
        faded
        class="!min-h-11"
        @click="$emit('criar')"
      />
    </div>
  </article>
</template>
