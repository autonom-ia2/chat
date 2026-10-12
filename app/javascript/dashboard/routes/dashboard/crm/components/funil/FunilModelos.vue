<script setup>
import { MODELOS } from './funil';

// #1384 — "Começar pronto": cada modelo é um cartão grande com ícone, nome e
// o caminho do cliente. O escolhido ganha a borda azul e o visto.
defineProps({
  modelo: { type: String, required: true },
});

defineEmits(['escolher']);
</script>

<template>
  <section class="flex flex-col gap-3">
    <h3
      id="funil-modelos-titulo"
      class="mb-0 text-base font-semibold text-n-slate-12"
    >
      {{ $t('CRM_FUNIL.MODELOS.ROTULO') }}
    </h3>
    <div
      class="grid gap-3 sm:grid-cols-3"
      role="group"
      aria-labelledby="funil-modelos-titulo"
    >
      <button
        v-for="item in MODELOS"
        :key="item.chave"
        type="button"
        :data-modelo="item.chave"
        :aria-pressed="modelo === item.chave"
        class="relative flex min-h-11 items-center gap-3 rounded-2xl border-2 p-4 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand sm:flex-col sm:items-start"
        :class="
          modelo === item.chave
            ? 'border-n-blue-8 bg-n-blue-2'
            : 'border-n-weak bg-n-solid-1 hover:border-n-slate-7'
        "
        @click="$emit('escolher', item.chave)"
      >
        <span
          class="grid size-11 shrink-0 place-items-center rounded-xl"
          :class="item.tom"
          aria-hidden="true"
        >
          <span class="size-5" :class="item.icone" />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span class="text-base font-semibold text-n-slate-12">
            {{ $t(`CRM_FUNIL.MODELOS.${item.chave}.NOME`) }}
          </span>
          <span class="text-sm text-n-slate-11">
            {{ $t(`CRM_FUNIL.MODELOS.${item.chave}.TEXTO`) }}
          </span>
        </span>
        <span
          v-if="modelo === item.chave"
          class="grid size-6 shrink-0 place-items-center rounded-full bg-n-blue-9 text-white sm:absolute sm:end-3 sm:top-3"
          aria-hidden="true"
        >
          <span class="i-lucide-check size-4" />
        </span>
      </button>
    </div>
  </section>
</template>
