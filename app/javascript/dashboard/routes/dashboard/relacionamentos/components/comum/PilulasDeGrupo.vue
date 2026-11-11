<script setup>
import { useI18n } from 'vue-i18n';

// #2894 — os grupos em pílulas, cada um com o seu número. A escolhida fica
// preenchida (aria-pressed, como a vitrine de ferramentas). No celular a fila
// rola para o lado; cada pílula tem 44 px de altura.
//   grupos: [{ id, nome, total }]    v-model: o id do grupo escolhido
defineProps({
  grupos: { type: Array, required: true },
  modelValue: { type: String, default: '' },
  rotulo: { type: String, default: '' },
});
const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();
</script>

<template>
  <nav
    class="min-w-0"
    :aria-label="rotulo || t('RELACIONAMENTOS.COMUM.GRUPOS')"
  >
    <ul
      class="flex gap-2 p-0 pb-1 m-0 overflow-x-auto list-none snap-x scroll-px-4"
    >
      <li v-for="grupo in grupos" :key="grupo.id" class="snap-start">
        <button
          type="button"
          :data-grupo="grupo.id"
          :aria-pressed="modelValue === grupo.id ? 'true' : 'false'"
          class="inline-flex items-center gap-2 px-4 text-sm font-medium rounded-full whitespace-nowrap min-h-11 ring-1 ring-inset focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-blue-11"
          :class="
            modelValue === grupo.id
              ? 'bg-n-blue-11 text-white ring-n-blue-11 dark:text-n-slate-1'
              : 'bg-n-solid-1 text-n-slate-12 ring-n-weak hover:bg-n-alpha-1'
          "
          @click="emit('update:modelValue', grupo.id)"
        >
          {{ grupo.nome }}
          <span
            v-if="grupo.total !== undefined && grupo.total !== null"
            class="tabular-nums opacity-75"
          >
            {{ grupo.total }}
          </span>
        </button>
      </li>
    </ul>
  </nav>
</template>
