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

// Como o menu de anexar do app: só o desenho colorido (sem bolinha atrás), nas
// cores do WhatsApp; ícones da biblioteca do painel. `separado`: linha antes,
// como a que separa Catálogo e Resposta rápida no app.
const ITENS = [
  // Os dois abrem o seletor de arquivo do clipe; "Fotos e vídeos" só mostra mídia.
  {
    tipo: 'anexo',
    chave: 'DOCUMENTO',
    icone: 'i-ph-file-text-fill',
    cor: 'text-[#7F66FF]',
  },
  {
    tipo: 'anexo',
    chave: 'FOTOS_E_VIDEOS',
    icone: 'i-ph-images-fill',
    cor: 'text-[#007BFC]',
    filtro: 'image/*,video/*',
  },
  {
    tipo: 'localizacao',
    chave: 'LOCALIZACAO',
    icone: 'i-ph-map-pin-fill',
    cor: 'text-[#1DAA61]',
  },
  {
    tipo: 'pedidoDeLocalizacao',
    chave: 'PEDIR_LOCALIZACAO',
    icone: 'i-ph-navigation-arrow-fill',
    cor: 'text-[#02A698]',
  },
  {
    tipo: 'contato',
    chave: 'CONTATO',
    icone: 'i-ph-user-fill',
    cor: 'text-[#009DE2]',
  },
  {
    tipo: 'opcoes',
    chave: 'OPCOES',
    icone: 'i-ph-chart-bar-horizontal-fill',
    cor: 'text-[#FFBC38]',
  },
  {
    tipo: 'botaoDeLink',
    chave: 'BOTAO_DE_LINK',
    icone: 'i-ph-link-bold',
    cor: 'text-[#FF2E74]',
  },
  {
    tipo: 'formulario',
    chave: 'FORMULARIO',
    icone: 'i-ph-note-pencil-fill',
    cor: 'text-[#8696A0]',
    soOficial: true,
    separado: true,
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
    emit('anexar', item.filtro);
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
      class="absolute bottom-full mb-2 ltr:left-0 rtl:right-0 z-30 w-[17rem] p-2 rounded-[1.25rem] bg-white dark:bg-[#233138] shadow-[0_4px_24px_rgba(11,20,26,0.18),0_1px_4px_rgba(11,20,26,0.12)] dark:shadow-[0_4px_24px_rgba(0,0,0,0.5)] dark:ring-1 dark:ring-white/10"
    >
      <p
        v-if="soTexto"
        class="px-3 pt-1 pb-2 text-[13px] leading-snug text-[#667781] dark:text-[#8696A0]"
        data-so-texto
      >
        {{ t('CONVERSA_CANAL.MAIS.SO_TEXTO') }}
      </p>
      <template v-for="item in itens" :key="item.chave">
        <hr
          v-if="item.separado"
          class="my-1.5 mx-3 border-0 border-t border-[#111B21]/10 dark:border-white/15"
          aria-hidden="true"
        />
        <button
          type="button"
          role="menuitem"
          class="flex items-center gap-4 w-full h-12 px-3 rounded-xl text-start text-base text-[#111B21] dark:text-[#E9EDEF] hover:bg-[#F5F6F6] dark:hover:bg-white/5 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#111B21] dark:focus-visible:ring-[#E9EDEF]"
          :data-item="
            item.tipo === 'anexo' ? item.chave.toLowerCase() : item.tipo
          "
          @click="escolher(item)"
        >
          <Icon
            :icon="item.icone"
            class="size-6 flex-shrink-0"
            :class="item.cor"
          />
          {{ t(`CONVERSA_CANAL.MAIS.${item.chave}`) }}
        </button>
      </template>
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
