<script setup>
// Botão redondo de descer (#1702): aparece no canto de baixo quando a conversa está
// rolada para cima e leva de volta à mensagem mais recente, como no app. Com o
// atendente lá em cima, o selo verde conta as mensagens do cliente que chegaram (e as
// não lidas abaixo da faixa); zera quando ele desce.
import {
  computed,
  onBeforeUnmount,
  onMounted,
  ref,
  useTemplateRef,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import {
  DISTANCIA_DO_FIM,
  distanciaDoFim,
  inicioDaContagem,
  novasDoCliente,
} from './rolagemDaPele';

const props = defineProps({
  // As mensagens que a lista mostra (camelCase).
  mensagens: { type: Array, default: () => [] },
  primeiraNaoLida: { type: Number, default: null },
});

const { t } = useI18n();
const raiz = useTemplateRef('raiz');
const visivel = ref(false);
let painel = null;
let observador = null;

const conferir = () => {
  if (!painel) return;
  visivel.value = distanciaDoFim(painel) > DISTANCIA_DO_FIM;
};

const descer = () =>
  painel?.scrollTo({ top: painel.scrollHeight, behavior: 'smooth' });

// A contagem começa na não lida da faixa (ao abrir a conversa) ou depois da última.
const desde = ref(null);
const recomecar = () => {
  desde.value = inicioDaContagem(props.mensagens, props.primeiraNaoLida);
};
const conversaId = computed(() => props.mensagens[0]?.conversationId);
const ultimaId = computed(
  () => props.mensagens[props.mensagens.length - 1]?.id
);
watch([conversaId, () => props.primeiraNaoLida], recomecar, {
  immediate: true,
});
// No fim da conversa não há o que contar: o que chegar dali em diante é novo.
watch([visivel, ultimaId], () => {
  if (!visivel.value) desde.value = inicioDaContagem(props.mensagens, null);
});

const novas = computed(() =>
  visivel.value ? novasDoCliente(props.mensagens, desde.value) : 0
);
const rotulo = computed(() =>
  novas.value
    ? `${t('CONVERSA_CANAL.MIDIA.DESCER')}. ${t('CONVERSA_CANAL.ROLAGEM.NOVAS', { n: novas.value }, novas.value)}`
    : t('CONVERSA_CANAL.MIDIA.DESCER')
);

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
      :aria-label="rotulo"
      :title="rotulo"
      @click="descer"
    >
      <Icon icon="i-ph-caret-down" class="size-6" />
      <span
        v-if="novas"
        class="absolute -top-2 ltr:-left-1 rtl:-right-1 min-w-[22px] h-[22px] px-1.5 grid place-content-center rounded-full bg-[#25D366] text-white dark:text-[#0B141A] text-[12px] font-semibold leading-none"
        data-novas-do-cliente
        aria-hidden="true"
      >
        {{ novas }}
      </span>
    </button>
  </li>
</template>
