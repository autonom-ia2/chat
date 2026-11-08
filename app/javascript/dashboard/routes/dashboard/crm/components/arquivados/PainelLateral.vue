<script setup>
import { computed, ref, useId } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import { useFocoPreso } from '../card/useFocoPreso';

// Casca dos painéis Arquivados e Funis arquivados (#2095): gaveta da direita, como a de filtros, com o foco preso
// enquanto aberta e devolvido a quem abriu. Esc fecha (com uma janela aberta por cima, a janela cuida do Esc).
const props = defineProps({
  show: { type: Boolean, default: false },
  titulo: { type: String, required: true },
  subtitulo: { type: String, default: '' },
});
const emit = defineEmits(['close']);
// Os atributos de quem usa (data-*) vão para a gaveta, não para a transição.
defineOptions({ inheritAttrs: false });

const { t } = useI18n();
const id = useId();
const raiz = ref(null);
const { prender } = useFocoPreso({
  raiz,
  mostrar: computed(() => props.show),
});

const aoTeclar = evento => {
  if (evento.key === 'Escape' && !document.querySelector('dialog[open]')) {
    evento.stopPropagation();
    emit('close');
    return;
  }
  prender(evento);
};
</script>

<template>
  <transition
    enter-active-class="transition duration-200 ease-out"
    enter-from-class="ltr:translate-x-full rtl:-translate-x-full opacity-0"
    leave-active-class="transition duration-150 ease-in"
    leave-to-class="ltr:translate-x-[30%] rtl:-translate-x-[30%] opacity-0"
  >
    <aside
      v-if="show"
      ref="raiz"
      role="dialog"
      aria-modal="true"
      :aria-labelledby="`${id}-titulo`"
      tabindex="-1"
      class="fixed inset-y-0 z-50 flex h-full w-[36rem] max-w-full flex-col overflow-hidden border-n-weak bg-n-surface-1 shadow-lg outline-none ltr:right-0 ltr:border-l rtl:left-0 rtl:border-r"
      v-bind="$attrs"
      @keydown="aoTeclar"
    >
      <header
        class="flex items-start justify-between gap-4 border-b border-n-weak px-5 py-4 sm:px-6"
      >
        <div class="min-w-0">
          <h2
            :id="`${id}-titulo`"
            class="mb-0 text-xl font-semibold text-n-slate-12"
          >
            {{ titulo }}
          </h2>
          <p
            v-if="subtitulo"
            data-painel-sub
            class="mb-0 mt-1 text-sm text-n-slate-11"
          >
            {{ subtitulo }}
          </p>
        </div>
        <Button
          icon="i-lucide-x"
          slate
          ghost
          data-painel-fechar
          :aria-label="t('CRM_ARQUIVADOS.FECHAR')"
          class="!min-h-11 !min-w-11"
          @click="emit('close')"
        />
      </header>
      <div class="min-h-0 flex-1 overflow-y-auto px-5 py-4 sm:px-6">
        <slot />
      </div>
    </aside>
  </transition>
</template>
