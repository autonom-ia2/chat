<script setup>
// O "+" da barra de digitar (#1702), como o clipe do WhatsApp: documento e foto usam o
// anexo de sempre; localização, contato, botão de link, opções e pedir localização
// abrem uma janela curta com a prévia do que o cliente vai ver.
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import JanelaDoMais from './JanelaDoMais.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  caixa: { type: Object, required: true },
  // pedido → Promise (o envio da caixa de resposta).
  enviar: { type: Function, required: true },
});

const emit = defineEmits(['anexar']);

const { t } = useI18n();
const aberto = ref(false);
const janela = ref(null);
const botaoRef = ref(null);

// WhatsApp oficial (Cloud API): tudo sai no formato do app e existe Formulário.
const ehOficial = computed(
  () =>
    props.caixa.channel_type === INBOX_TYPES.WHATSAPP &&
    props.caixa.provider === 'whatsapp_cloud'
);
// Caixa híbrida fora das 24 h: sai pelo número reserva, só texto. O servidor já decide
// isso em `whatsapp_api_reply`, o mesmo campo do aviso de hoje.
const conversa = useMapGetter('getSelectedChat');
const soTexto = computed(() => Boolean(conversa.value?.whatsapp_api_reply));
// Em texto: WAHA, 360dialog (o envio do #1473 só é nativo na Cloud API) e número reserva.
const viraTexto = computed(() => !ehOficial.value || soTexto.value);

// Cores e ordem inspiradas no menu do app; ícones da biblioteca do painel.
const ITENS = [
  // Um item só para arquivo: o seletor do painel é o mesmo para foto, vídeo e documento.
  {
    tipo: 'anexo',
    chave: 'ARQUIVO',
    icone: 'i-ph-paperclip-bold',
    cor: 'bg-[#7F66FF]',
  },
  {
    tipo: 'localizacao',
    chave: 'LOCALIZACAO',
    icone: 'i-ph-map-pin-fill',
    cor: 'bg-[#1DAA61]',
  },
  {
    tipo: 'pedidoDeLocalizacao',
    chave: 'PEDIR_LOCALIZACAO',
    icone: 'i-ph-navigation-arrow-fill',
    cor: 'bg-[#00A884]',
  },
  {
    tipo: 'contato',
    chave: 'CONTATO',
    icone: 'i-ph-user-circle-fill',
    cor: 'bg-[#009DE2]',
  },
  {
    tipo: 'botaoDeLink',
    chave: 'BOTAO_DE_LINK',
    icone: 'i-ph-link-bold',
    cor: 'bg-[#02A698]',
  },
  {
    tipo: 'opcoes',
    chave: 'OPCOES',
    icone: 'i-ph-list-checks-bold',
    cor: 'bg-[#FFBC38]',
  },
  {
    tipo: 'formulario',
    chave: 'FORMULARIO',
    icone: 'i-ph-note-pencil-bold',
    cor: 'bg-[#5157AE]',
    soOficial: true,
  },
];
// Formulário só sai nativo. No número reserva arquivo não vai: o item some e o menu avisa.
const itens = computed(() =>
  ITENS.filter(
    item =>
      (!item.soOficial || !viraTexto.value) &&
      (item.tipo !== 'anexo' || !soTexto.value)
  )
);

const fechar = () => {
  aberto.value = false;
};

const escolher = item => {
  fechar();
  if (item.tipo === 'anexo') {
    emit('anexar');
    return;
  }
  janela.value?.abrir(item.tipo);
};

const menuRef = ref(null);
const itensDoMenu = () => [
  ...(menuRef.value?.querySelectorAll('[role=menuitem]') || []),
];
const focar = indice => {
  const lista = itensDoMenu();
  lista[(indice + lista.length) % lista.length]?.focus();
};
const alternar = async () => {
  aberto.value = !aberto.value;
  if (!aberto.value) return;
  await nextTick();
  focar(0);
};

// Menu WAI-ARIA: setas e Home/End andam pelos itens; Esc fecha e volta ao "+".
const aoTeclar = evento => {
  if (evento.key === 'Escape') {
    fechar();
    botaoRef.value?.focus();
    return;
  }
  if (!aberto.value) return;
  const atual = itensDoMenu().indexOf(document.activeElement);
  const MOVER = { ArrowDown: atual + 1, ArrowUp: atual - 1, Home: 0, End: -1 };
  if (!(evento.key in MOVER)) return;
  evento.preventDefault();
  focar(MOVER[evento.key]);
};
</script>

<template>
  <div class="relative" @keydown="aoTeclar">
    <button
      ref="botaoRef"
      type="button"
      class="grid place-content-center size-11 rounded-full text-[#54656F] dark:text-[#AEBAC1] hover:bg-[#111B21]/5 dark:hover:bg-white/5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#00A884]"
      :class="{ 'bg-[#111B21]/10 dark:bg-white/10': aberto }"
      :aria-label="t('CONVERSA_CANAL.MAIS.ABRIR')"
      :aria-expanded="aberto"
      aria-haspopup="menu"
      data-mais-do-whatsapp
      @click="alternar"
    >
      <Icon
        icon="i-lucide-plus"
        class="size-6 transition-transform"
        :class="{ 'rotate-45': aberto }"
      />
    </button>
    <div
      v-if="aberto"
      ref="menuRef"
      v-on-click-outside="[fechar, { ignore: [botaoRef] }]"
      role="menu"
      class="absolute bottom-full mb-2 ltr:left-0 rtl:right-0 z-30 w-64 py-2 rounded-2xl bg-white dark:bg-[#233138] shadow-[0_2px_5px_rgba(11,20,26,0.26),0_2px_10px_rgba(11,20,26,0.16)]"
    >
      <p
        v-if="soTexto"
        class="px-4 pt-1 pb-2 text-[13px] leading-snug text-[#667781] dark:text-[#8696A0]"
        data-so-texto
      >
        {{ t('CONVERSA_CANAL.MAIS.SO_TEXTO') }}
      </p>
      <button
        v-for="item in itens"
        :key="item.chave"
        type="button"
        role="menuitem"
        class="flex items-center gap-3 w-full min-h-11 px-4 py-2 text-start text-[15px] text-[#3B4A54] dark:text-[#D1D7DB] hover:bg-[#F5F6F6] dark:hover:bg-[#182229] focus-visible:bg-[#F5F6F6] dark:focus-visible:bg-[#182229] outline-none"
        :data-item="
          item.tipo === 'anexo' ? item.chave.toLowerCase() : item.tipo
        "
        @click="escolher(item)"
      >
        <span
          class="grid place-content-center size-8 rounded-full text-white flex-shrink-0"
          :class="item.cor"
        >
          <Icon :icon="item.icone" class="size-4" />
        </span>
        {{ t(`CONVERSA_CANAL.MAIS.${item.chave}`) }}
      </button>
    </div>
    <JanelaDoMais
      ref="janela"
      :inbox-id="caixa.id"
      :vira-texto="viraTexto"
      :enviar="enviar"
      @fechou="botaoRef?.focus()"
    />
  </div>
</template>
