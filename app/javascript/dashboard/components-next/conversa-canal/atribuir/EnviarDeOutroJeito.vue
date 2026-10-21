<script setup>
// #2067, forma C do protótipo: a setinha colada no Enviar. O Enviar faz o padrão (ficar
// com a conversa sem ninguém ou com a IA; só enviar na conversa de colega); a setinha
// oferece o outro jeito, só para esta mensagem.
import { computed, ref } from 'vue';
import { onClickOutside } from '@vueuse/core';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  ficar: { type: Object, required: true },
  enviar: { type: Function, required: true },
  desligado: { type: Boolean, default: false },
});

const { t } = useI18n();
const aberto = ref(false);
const raiz = ref(null);
onClickOutside(raiz, () => {
  aberto.value = false;
});

const outroJeito = computed(() =>
  props.ficar.ligada
    ? {
        ficar: false,
        texto: t('CONVERSA_CANAL.FICAR.SO_ENVIAR'),
        icone: 'i-lucide-send',
      }
    : {
        ficar: true,
        texto: t('CONVERSA_CANAL.FICAR.ENVIAR_E_FICAR'),
        icone: 'i-lucide-user-round-check',
      }
);

const escolher = () => {
  aberto.value = false;
  props.ficar.enviarAssim(outroJeito.value.ficar, props.enviar);
};
</script>

<template>
  <div ref="raiz" class="relative flex self-center">
    <button
      v-tooltip.top-end="aberto ? null : t('CONVERSA_CANAL.FICAR.MAIS_OPCOES_DE_ENVIO')"
      type="button"
      :aria-label="t('CONVERSA_CANAL.FICAR.MAIS_OPCOES_DE_ENVIO')"
      aria-haspopup="menu"
      :aria-expanded="aberto"
      :disabled="desligado"
      data-enviar-de-outro-jeito
      class="grid h-10 w-6 rounded-full place-content-center text-n-slate-11 hover:enabled:bg-n-alpha-2 disabled:opacity-40 outline-none focus-visible:ring-2 focus-visible:ring-n-blue-8"
      @click="aberto = !aberto"
    >
      <span
        class="i-lucide-chevron-up size-4 transition-transform"
        :class="{ 'rotate-180': aberto }"
        aria-hidden="true"
      />
    </button>
    <div
      v-if="aberto"
      role="menu"
      class="absolute z-50 p-1 bottom-full mb-2 end-0 w-max rounded-xl bg-n-alpha-3 backdrop-blur-[100px] shadow-lg outline outline-1 outline-n-container"
    >
      <button
        type="button"
        role="menuitem"
        class="flex items-center w-full gap-2 px-3 text-sm whitespace-nowrap text-start rounded-lg min-h-11 text-n-slate-12 hover:bg-n-alpha-2 focus-visible:bg-n-alpha-2 outline-none"
        @click="escolher"
      >
        <span :class="outroJeito.icone" class="size-4 flex-shrink-0 text-n-slate-11" />
        {{ outroJeito.texto }}
      </button>
    </div>
  </div>
</template>
