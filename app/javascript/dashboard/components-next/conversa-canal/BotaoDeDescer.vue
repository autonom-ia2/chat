<script setup>
// Botão redondo de descer (#1702): aparece no canto de baixo quando a conversa está
// rolada para cima e leva de volta à mensagem mais recente, como no app.
import { onBeforeUnmount, onMounted, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

// A partir de quanto rolado para cima o botão aparece.
const DISTANCIA_PARA_MOSTRAR = 300;

const { t } = useI18n();
const raiz = useTemplateRef('raiz');
const visivel = ref(false);
let painel = null;
let observador = null;

const conferir = () => {
  if (!painel) return;
  const falta = painel.scrollHeight - painel.scrollTop - painel.clientHeight;
  visivel.value = falta > DISTANCIA_PARA_MOSTRAR;
};

const descer = () =>
  painel?.scrollTo({ top: painel.scrollHeight, behavior: 'smooth' });

onMounted(() => {
  painel = raiz.value?.closest('.conversation-panel') || null;
  painel?.addEventListener('scroll', conferir, { passive: true });
  // Mensagem nova aumenta a conversa sem rolar: o tamanho da lista também confere.
  const lista = raiz.value?.parentElement;
  if (lista && window.ResizeObserver) {
    observador = new ResizeObserver(conferir);
    observador.observe(lista);
  }
  conferir();
});
onBeforeUnmount(() => {
  painel?.removeEventListener('scroll', conferir);
  observador?.disconnect();
});
</script>

<template>
  <li
    ref="raiz"
    class="sticky bottom-3 z-10 h-0 list-none flex justify-end overflow-visible"
    data-botao-de-descer
  >
    <button
      v-show="visivel"
      type="button"
      class="absolute bottom-0 ltr:-right-[3%] rtl:-left-[3%] grid place-content-center size-[42px] rounded-full bg-white dark:bg-[#242626] text-[#3B3B3B] dark:text-[#A7A8A8] shadow-[0_1px_3px_rgba(0,0,0,0.2)] hover:bg-[#F5F5F5] dark:hover:bg-[#2E3030]"
      :aria-label="t('CONVERSA_CANAL.MIDIA.DESCER')"
      :title="t('CONVERSA_CANAL.MIDIA.DESCER')"
      @click="descer"
    >
      <Icon icon="i-ph-caret-down" class="size-6" />
    </button>
  </li>
</template>
