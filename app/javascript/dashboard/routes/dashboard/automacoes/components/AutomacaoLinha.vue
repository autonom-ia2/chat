<script setup>
import Switch from 'dashboard/components-next/switch/Switch.vue';

// #859 — uma automação na lista: a frase em português, o nome, o selo de quem
// criou e o interruptor. A frase inteira é o botão que abre a automação.
defineProps({
  automacao: { type: Object, required: true },
  frase: { type: String, required: true },
  criadaPeloGuia: { type: Boolean, default: false },
  podeMudar: { type: Boolean, default: false },
  mudando: { type: Boolean, default: false },
});

const emit = defineEmits(['abrir', 'alternar']);
</script>

<template>
  <li
    class="flex flex-col gap-2 sm:flex-row sm:items-center rounded-xl border border-n-weak bg-n-solid-1 p-4"
  >
    <button
      type="button"
      data-abrir
      class="flex-1 min-w-0 min-h-11 text-start rounded-lg focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
      :title="$t('AUTOMACOES.LISTA.ABRIR', { nome: automacao.name })"
      @click="emit('abrir')"
    >
      <span class="block text-sm leading-6 text-n-slate-12 break-words">
        {{ frase }}
      </span>
      <span
        class="flex flex-wrap items-center gap-2 mt-1 text-xs text-n-slate-11"
      >
        <span class="truncate">{{ automacao.name }}</span>
        <span
          v-if="criadaPeloGuia"
          data-selo-guia
          class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-n-iris-3 text-n-iris-11"
        >
          <span class="i-lucide-sparkles size-3" aria-hidden="true" />
          {{ $t('AUTOMACOES.LISTA.SELO_GUIA') }}
        </span>
      </span>
    </button>
    <label
      class="flex items-center gap-2 min-h-11 px-2 shrink-0 select-none"
      :class="
        podeMudar && !mudando
          ? 'cursor-pointer'
          : 'cursor-not-allowed opacity-60'
      "
    >
      <Switch
        data-interruptor
        :model-value="automacao.active"
        :disabled="!podeMudar || mudando"
        @update:model-value="emit('alternar')"
      />
      <span class="text-sm text-n-slate-11">
        {{
          automacao.active
            ? $t('AUTOMACOES.LISTA.LIGADA')
            : $t('AUTOMACOES.LISTA.DESLIGADA')
        }}
      </span>
    </label>
  </li>
</template>
