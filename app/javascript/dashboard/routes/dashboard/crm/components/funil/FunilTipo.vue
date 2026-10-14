<script setup>
import { TIPOS } from './funil';

// #1498 — "Para que serve este funil?": dois cartões grandes, Vender e
// Atender. É a única escolha nova; o resto vem pronto do tipo escolhido.
// `compacto` é a mesma pergunta dentro de "Alterar", num funil que já existe.
defineProps({
  tipo: { type: String, default: '' },
  compacto: { type: Boolean, default: false },
});

defineEmits(['escolher']);
</script>

<template>
  <section class="flex flex-col gap-3" data-funil-tipo>
    <header class="flex flex-col gap-1">
      <h3
        id="funil-tipo-titulo"
        class="mb-0 font-semibold text-n-slate-12"
        :class="compacto ? 'text-base' : 'text-xl'"
      >
        {{ $t('CRM_FUNIL.TIPO.PERGUNTA') }}
      </h3>
      <p v-if="!compacto" class="mb-0 text-[0.9375rem] text-n-slate-11">
        {{ $t('CRM_FUNIL.TIPO.AJUDA') }}
      </p>
    </header>
    <div
      class="grid gap-3 sm:grid-cols-2"
      role="group"
      aria-labelledby="funil-tipo-titulo"
    >
      <button
        v-for="item in TIPOS"
        :key="item.chave"
        type="button"
        :data-tipo="item.chave"
        :aria-pressed="tipo === item.chave"
        class="relative flex min-h-11 items-center gap-4 rounded-2xl border-2 text-start transition focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-n-brand"
        :class="[
          compacto ? 'p-4' : 'p-5 sm:min-h-[8.5rem] sm:flex-col sm:items-start',
          tipo === item.chave
            ? 'border-n-blue-9 bg-n-blue-2'
            : 'border-n-slate-5 bg-n-solid-1 shadow-sm hover:border-n-slate-8',
        ]"
        @click="$emit('escolher', item.chave)"
      >
        <span
          class="grid shrink-0 place-items-center rounded-2xl"
          :class="[item.tom, compacto ? 'size-11' : 'size-12 sm:size-14']"
          aria-hidden="true"
        >
          <span
            :class="[item.icone, compacto ? 'size-5' : 'size-6 sm:size-7']"
          />
        </span>
        <span class="flex min-w-0 flex-1 flex-col gap-0.5">
          <span
            class="font-semibold text-n-slate-12"
            :class="compacto ? 'text-base' : 'text-lg'"
          >
            {{ $t(`CRM_FUNIL.TIPO.${item.chave}.NOME`) }}
          </span>
          <span class="text-[0.9375rem] text-n-slate-11">
            {{ $t(`CRM_FUNIL.TIPO.${item.chave}.TEXTO`) }}
          </span>
        </span>
        <span
          v-if="tipo === item.chave"
          class="grid size-6 shrink-0 place-items-center rounded-full bg-n-blue-9 text-white sm:absolute sm:end-3 sm:top-3"
          aria-hidden="true"
        >
          <span class="i-lucide-check size-4" />
        </span>
      </button>
    </div>
  </section>
</template>
