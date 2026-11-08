<script setup>
// #2211 — a gaveta "Por onde mandar?" da conversa vazia, quando a pessoa tem mais de uma
// caixa possível. Cada opção: o ícone do canal, o nome da caixa e, embaixo, o número ou o
// e-mail por onde a mensagem sai. Escolher fecha a gaveta.
import { onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { linhaDaCaixa } from './caixasDaConversaVazia';
import { iconeDaCaixa } from '../iconeDaCaixa';

defineProps({
  caixas: { type: Array, default: () => [] },
  escolhida: { type: [Number, String], default: null },
  semInstagram: { type: Boolean, default: false },
});
const emit = defineEmits(['escolher', 'fechar']);

const { t } = useI18n();
const lista = ref(null);

// Abriu (quem abre e fecha é a tela, com v-if): o foco vai para a escolhida (ou a primeira),
// para o teclado seguir dali.
onMounted(() => {
  const alvo =
    lista.value?.querySelector('[aria-pressed="true"]') ||
    lista.value?.querySelector('button');
  alvo?.focus();
});
</script>

<template>
  <div
    class="absolute inset-0 z-20 flex justify-end bg-n-alpha-black1"
    data-por-onde-mandar
    @click.self="emit('fechar')"
    @keydown.esc.stop="emit('fechar')"
  >
    <section
      role="dialog"
      aria-modal="true"
      aria-labelledby="por-onde-mandar-titulo"
      class="flex flex-col w-full h-full shadow-xl sm:w-96 bg-n-solid-1"
    >
      <header
        class="flex items-center justify-between gap-3 px-5 py-4 border-b border-n-weak"
      >
        <h2
          id="por-onde-mandar-titulo"
          class="m-0 text-base font-semibold text-n-slate-12"
        >
          {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.POR_ONDE') }}
        </h2>
        <button
          type="button"
          class="flex items-center justify-center bg-transparent border-0 rounded-lg size-11 text-n-slate-11 hover:bg-n-alpha-2"
          :aria-label="t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.FECHAR')"
          @click="emit('fechar')"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
        </button>
      </header>
      <ul ref="lista" class="flex flex-col gap-1 p-3 m-0 overflow-y-auto">
        <li v-for="caixa in caixas" :key="caixa.id" class="list-none">
          <button
            type="button"
            data-opcao-de-caixa
            :aria-pressed="String(caixa.id) === String(escolhida)"
            class="flex items-center w-full gap-3 px-3 py-2 bg-transparent border border-transparent rounded-xl min-h-14 text-start hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand aria-pressed:border-n-brand aria-pressed:bg-n-alpha-1"
            @click="emit('escolher', caixa.id)"
          >
            <span
              class="flex items-center justify-center flex-shrink-0 rounded-full size-9 bg-n-alpha-2 text-n-slate-12"
              aria-hidden="true"
            >
              <span class="size-5" :class="iconeDaCaixa(caixa)" />
            </span>
            <span class="flex flex-col min-w-0">
              <span class="text-sm font-medium truncate text-n-slate-12">
                {{ caixa.name }}
              </span>
              <span
                v-if="linhaDaCaixa(caixa)"
                class="text-xs truncate text-n-slate-11"
              >
                {{ linhaDaCaixa(caixa) }}
              </span>
            </span>
          </button>
        </li>
      </ul>
      <p
        v-if="semInstagram"
        class="flex gap-2 px-5 py-3 m-0 mt-auto text-xs border-t border-n-weak text-n-slate-11"
      >
        <span class="i-lucide-info size-4 flex-shrink-0" aria-hidden="true" />
        {{ t('LISTA_DE_CONVERSAS.CONVERSA_VAZIA.SEM_INSTAGRAM') }}
      </p>
    </section>
  </div>
</template>
