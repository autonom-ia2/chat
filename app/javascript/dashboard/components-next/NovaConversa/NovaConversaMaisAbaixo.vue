<script setup>
// Quando a gaveta tem mais conteúdo do que cabe na tela, a borda de baixo esmaece e um
// chevron duplo, transparente, avisa que dá para descer. É o mesmo indicador do menu
// lateral (#1781, useSetasDeRolagem): respira duas vezes ao aparecer (nada se mexe com
// movimento reduzido), e o toque, um círculo invisível de 44 px, rola uma tela.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useSetasDeRolagem } from 'dashboard/components-next/sidebar/fork/useSetasDeRolagem';

const props = defineProps({
  // O elemento que rola e o conteúdo dentro dele (para medir quando cresce).
  caixa: { type: Object, default: null },
  conteudo: { type: Object, default: null },
  controla: { type: String, required: true },
});

const { t } = useI18n();
// O composable lê `.value`: refs computados, não funções.
const setas = useSetasDeRolagem(
  computed(() => props.caixa),
  computed(() => props.conteudo)
);
</script>

<template>
  <div
    v-if="setas.abaixo.value"
    data-esmaecido-da-gaveta
    aria-hidden="true"
    class="pointer-events-none absolute inset-x-0 bottom-0 z-[1] h-14 bg-gradient-to-t from-n-solid-1 via-n-solid-1/80 to-transparent"
  />
  <Transition
    enter-active-class="transition duration-200 ease-out motion-reduce:transition-none"
    leave-active-class="transition duration-200 ease-in motion-reduce:transition-none"
    enter-from-class="opacity-0 translate-y-1"
    leave-to-class="opacity-0 translate-y-1"
  >
    <button
      v-if="setas.abaixo.value"
      type="button"
      data-mais-abaixo
      :aria-label="t('NOVA_CONVERSA.MAIS_ABAIXO')"
      :aria-controls="controla"
      class="group absolute inset-x-0 bottom-0 z-[2] mx-auto flex size-11 items-center justify-center rounded-full focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-brand"
      @click="setas.rolarParaBaixo"
    >
      <span
        class="i-lucide-chevrons-down size-6 text-n-slate-11 opacity-70 drop-shadow-[0_2px_6px_rgba(0,0,0,0.25)] transition duration-300 ease-in-out group-hover:scale-110 group-hover:text-n-slate-12 group-hover:opacity-100 motion-reduce:transition-none"
        :class="
          setas.respirando.value.abaixo ? 'translate-y-0.5' : 'translate-y-0'
        "
        aria-hidden="true"
      />
    </button>
  </Transition>
</template>
