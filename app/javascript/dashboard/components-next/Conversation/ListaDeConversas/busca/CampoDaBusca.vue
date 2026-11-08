<script setup>
// #2211 — o campo "Buscar conversa" no topo da lista, acima dos funis e das abas. O ✕ (ou Esc)
// limpa e a lista volta como estava. ⌘/Ctrl+K foca o campo (atalhoDaBusca).
import { nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { focoAtendido, pedidoDeFoco } from './atalhoDaBusca';

const emit = defineEmits(['limpar']);
const texto = defineModel({ type: String, default: '' });

const { t } = useI18n();
const campo = ref(null);

const focar = async () => {
  focoAtendido.value = pedidoDeFoco.value;
  await nextTick();
  campo.value?.focus();
  campo.value?.select();
};

watch(pedidoDeFoco, focar);
onMounted(() => {
  if (pedidoDeFoco.value > focoAtendido.value) focar();
});

const limpar = () => {
  texto.value = '';
  emit('limpar');
  campo.value?.focus();
};
</script>

<template>
  <div class="px-4 pb-2" data-busca-da-lista>
    <label
      class="flex items-center gap-2 px-3 h-10 rounded-lg bg-n-alpha-1 outline outline-1 outline-n-weak focus-within:outline-n-brand"
    >
      <span
        class="flex-shrink-0 i-lucide-search size-4 text-n-slate-11"
        aria-hidden="true"
      />
      <input
        ref="campo"
        v-model="texto"
        type="search"
        data-campo-da-busca
        autocomplete="off"
        enterkeyhint="search"
        maxlength="100"
        class="flex-1 min-w-0 !h-auto !p-0 !m-0 text-sm !bg-transparent !border-0 !rounded-none !shadow-none !outline-none appearance-none text-n-slate-12 placeholder:text-n-slate-10 [&::-webkit-search-cancel-button]:hidden"
        :placeholder="t('LISTA_DE_CONVERSAS.BUSCA.CAMPO')"
        :aria-label="t('LISTA_DE_CONVERSAS.BUSCA.CAMPO_ARIA')"
        @keydown.esc.prevent="limpar"
      />
      <button
        v-if="texto"
        type="button"
        data-limpar-busca
        class="relative flex items-center justify-center flex-shrink-0 p-0 border-0 rounded-full size-6 bg-n-alpha-2 text-n-slate-11 hover:text-n-slate-12 after:absolute after:-inset-2.5 after:content-['']"
        :aria-label="t('LISTA_DE_CONVERSAS.BUSCA.LIMPAR')"
        @click="limpar"
      >
        <span class="i-lucide-x size-3.5" aria-hidden="true" />
      </button>
    </label>
  </div>
</template>
