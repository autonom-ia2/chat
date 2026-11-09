<script setup>
import { ref } from 'vue';
import { useModalFocus } from 'dashboard/components-next/CampaignJourney/useModalFocus';

// #2692 — a casca das gavetas e folhas da Prospecção nova (v4, 3.0): painel à
// direita em 1280 e tela cheia em 390, acima do botão redondo do menu (z-50 >
// z-40). O foco fica preso dentro (useModalFocus, o mesmo de Campanhas), Esc
// fecha e o foco volta para quem abriu. O rodapé não precisa da margem do menu:
// o painel cobre o botão.
// Rodada 2:
// - uma largura só para todo painel (30rem), em toda tela;
// - o foco inicial vai para o título (não para "Fechar"), sem anel aceso;
// - painel aberto de dentro de outro tem "Voltar" à esquerda (`voltar`).
// Rodada 4: um padrão só. Painel de primeiro nível fecha com "Fechar" + X no
// topo; subpainel tem a seta no topo e "Cancelar" no rodapé.
defineProps({
  titulo: { type: String, required: true },
  voltar: { type: Boolean, default: false },
});
const emit = defineEmits(['close']);

const painel = ref(null);
const topo = ref(null);
useModalFocus({
  container: painel,
  initial: topo,
  onClose: () => emit('close'),
});
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex justify-end bg-n-slate-12/30"
    @click.self="emit('close')"
  >
    <section
      ref="painel"
      role="dialog"
      aria-modal="true"
      :aria-label="titulo"
      tabindex="-1"
      class="flex flex-col w-full h-full shadow-2xl outline-none bg-n-solid-1 md:w-[30rem] md:border-s md:border-n-weak"
      data-painel
    >
      <header
        class="flex items-start justify-between gap-3 px-5 pt-5 pb-3 border-b border-n-weak"
      >
        <button
          v-if="voltar"
          type="button"
          class="grid -ms-2 rounded-xl shrink-0 size-11 place-items-center text-n-slate-11 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :aria-label="$t('PROSPECTING_ACHAR.COMUM.VOLTAR')"
          data-voltar
          @click="emit('close')"
        >
          <span
            class="i-lucide-arrow-left size-5 rtl:rotate-180"
            aria-hidden="true"
          />
        </button>
        <div
          ref="topo"
          tabindex="-1"
          class="flex flex-col flex-1 min-w-0 gap-2 pt-1.5 outline-none"
        >
          <slot name="topo">
            <h2 class="m-0 text-xl font-semibold text-n-slate-12">
              {{ titulo }}
            </h2>
          </slot>
        </div>
        <button
          v-if="!voltar"
          type="button"
          class="flex items-center gap-1.5 px-3 text-sm font-medium rounded-xl shrink-0 min-h-11 text-n-slate-11 hover:bg-n-slate-3 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          data-fechar
          @click="emit('close')"
        >
          <span class="i-lucide-x size-5" aria-hidden="true" />
          {{ $t('PROSPECTING_ACHAR.COMUM.FECHAR') }}
        </button>
      </header>
      <div class="flex flex-col flex-1 gap-5 px-5 pt-5 pb-8 overflow-y-auto">
        <slot />
      </div>
      <footer
        v-if="$slots.rodape"
        class="flex flex-col gap-2 p-4 border-t border-n-weak bg-n-solid-1"
      >
        <slot name="rodape" />
      </footer>
    </section>
  </div>
</template>
