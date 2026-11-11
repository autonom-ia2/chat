<script setup>
import { ref, toRef, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';
import { useFocoPreso } from 'dashboard/components-next/NovaConversa/useFocoPreso';

// #2894 — a gaveta que abre à direita (tela cheia no celular): foco preso, Esc
// fecha, o foco volta para quem abriu e o título recebe o foco quando não há
// campo marcado com `data-foco`. O conteúdo vem nos slots `default` e `rodape`.
const props = defineProps({
  aberta: { type: Boolean, default: false },
  titulo: { type: String, required: true },
  largura: { type: String, default: 'sm:w-[28rem]' },
  marca: { type: String, default: '' },
});
const emit = defineEmits(['fechar']);

const { t } = useI18n();
const raiz = ref(null);
const idDoTitulo = useId();
const { prender } = useFocoPreso(raiz, toRef(props, 'aberta'));

// O Esc de uma lista aberta dentro da gaveta já foi tratado (a lista o consome).
const aoTeclar = evento => {
  prender(evento);
  if (evento.key === 'Escape' && !evento.defaultPrevented) emit('fechar');
};
</script>

<template>
  <TeleportWithDirection to="body">
    <div
      v-if="aberta"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-n-alpha-black1"
      @click="emit('fechar')"
    />
    <transition
      enter-active-class="transition duration-200 ease-out"
      enter-from-class="opacity-0 ltr:translate-x-full rtl:-translate-x-full"
      leave-active-class="transition duration-150 ease-in"
      leave-to-class="opacity-0 ltr:translate-x-[30%] rtl:-translate-x-[30%]"
    >
      <div
        v-if="aberta"
        ref="raiz"
        role="dialog"
        aria-modal="true"
        :aria-labelledby="idDoTitulo"
        :data-relacionamentos="marca || undefined"
        class="fixed inset-y-0 z-50 flex flex-col w-full h-full shadow-2xl bg-n-solid-1 ltr:right-0 rtl:left-0"
        :class="largura"
        @keydown="aoTeclar"
      >
        <header
          class="flex items-start justify-between gap-3 px-5 py-5 border-b border-n-weak sm:px-6"
        >
          <h2
            :id="idDoTitulo"
            data-view-title
            tabindex="-1"
            class="m-0 text-2xl font-bold tracking-tight text-n-slate-12 focus:outline-none"
          >
            {{ titulo }}
          </h2>
          <button
            type="button"
            :aria-label="t('RELACIONAMENTOS_FICHA.GAVETA.FECHAR')"
            class="inline-flex items-center justify-center rounded-xl size-11 shrink-0 text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            @click="emit('fechar')"
          >
            <span class="i-lucide-x size-5" aria-hidden="true" />
          </button>
        </header>
        <div class="flex-1 min-h-0 px-5 py-5 overflow-y-auto sm:px-6">
          <slot />
        </div>
        <footer
          v-if="$slots.rodape"
          class="flex flex-wrap gap-3 px-5 pt-4 pb-[calc(1rem+env(safe-area-inset-bottom))] border-t border-n-weak sm:px-6 [&>*]:flex-1 sm:[&>*]:flex-none"
        >
          <slot name="rodape" />
        </footer>
      </div>
    </transition>
  </TeleportWithDirection>
</template>
