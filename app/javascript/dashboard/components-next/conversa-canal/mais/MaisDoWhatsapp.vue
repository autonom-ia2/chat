<script setup>
// O "+" da barra de digitar (#1702), como o clipe do WhatsApp: documento e fotos
// e vídeos entram no anexo de sempre, cada um pelo seu seletor; localização, contato, botão de link, opções e pedir localização
// abrem uma janela curta com a prévia do que o cliente vai ver. A enquete só aparece
// onde o servidor a aceita (enqueteNoMais.js).
import { computed, nextTick, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import JanelaDoMais from './JanelaDoMais.vue';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useMapGetter } from 'dashboard/composables/store';
import { ENQUETE, FLAG_DA_ENQUETE, comoSaiAEnquete } from './enqueteNoMais';

const props = defineProps({
  caixa: { type: Object, required: true },
  // pedido → Promise (o envio da caixa de resposta).
  enviar: { type: Function, required: true },
  // #2211: antes de existir conversa (conversa vazia da busca), só Documento e Fotos e vídeos:
  // localização, contato e os outros saem numa conversa que já existe.
  soArquivos: { type: Boolean, default: false },
});

const emit = defineEmits(['arquivos']);

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
// Caixa híbrida fora das 24 h: sai pelo número reserva. Arquivo vai (sendFile/sendImage/
// sendVoice do WAHA); os formatos próprios da Meta viram texto. O servidor já decide
// isso em `whatsapp_api_reply`, o mesmo campo do aviso de hoje.
const conversa = useMapGetter('getSelectedChat');
const pelaReserva = computed(() => Boolean(conversa.value?.whatsapp_api_reply));
// Em texto: WAHA, 360dialog (o envio do #1473 só é nativo na Cloud API) e número reserva.
const viraTexto = computed(() => !ehOficial.value || pelaReserva.value);

const contaAtual = useMapGetter('getCurrentAccountId');
const flagDaConta = useMapGetter('accounts/isFeatureEnabledonAccount');
const enquete = computed(() =>
  comoSaiAEnquete({
    flagLigada: Boolean(flagDaConta.value(contaAtual.value, FLAG_DA_ENQUETE)),
    conversa: conversa.value,
  })
);

// Como o menu de anexar do app: só o desenho colorido (sem bolinha atrás), nas
// cores do WhatsApp; ícones da biblioteca do painel. `separado`: linha antes,
// como a que separa Catálogo e Resposta rápida no app.
// Seletor próprio de cada item de arquivo: o campo do clipe do Chatwoot fica intacto.
const SELETORES = {
  documento: { comoDocumento: true },
  fotos_e_videos: { filtro: 'image/*,video/*', comoDocumento: false },
};
const ITENS = [
  // Como no app: "Documento" manda qualquer arquivo como documento (foto e vídeo
  // chegam como arquivo, sem compactar); "Fotos e vídeos" manda como mídia, só
  // com foto e vídeo. Cada um tem o seu seletor (SELETORES).
  {
    tipo: 'documento',
    chave: 'DOCUMENTO',
    icone: 'i-ph-file-text-fill',
    cor: 'text-[#7F66FF]',
  },
  {
    tipo: 'fotos_e_videos',
    chave: 'FOTOS_E_VIDEOS',
    icone: 'i-ph-images-fill',
    cor: 'text-[#007BFC]',
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
    tipo: 'enquete',
    chave: 'ENQUETE',
    icone: 'i-ph-chart-bar-fill',
    cor: 'text-[#FFBC38]',
    soComEnquete: true,
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
    cor: 'text-[#A7A8A8]',
    soOficial: true,
    separado: true,
  },
];
// Formulário só sai nativo.
const itens = computed(() =>
  ITENS.filter(
    item =>
      (!item.soOficial || !viraTexto.value) &&
      (!item.soComEnquete || Boolean(enquete.value)) &&
      (!props.soArquivos || Boolean(SELETORES[item.tipo]))
  )
);

const fechar = () => {
  aberto.value = false;
};

const seletores = {};
const guardarSeletor = tipo => campo => {
  seletores[tipo] = campo;
};

const escolher = item => {
  fechar();
  if (SELETORES[item.tipo]) {
    seletores[item.tipo]?.click();
    return;
  }
  janela.value?.abrir(item.tipo);
};

const escolheuArquivos = (tipo, evento) => {
  const arquivos = [...(evento.target.files || [])];
  // eslint-disable-next-line no-param-reassign
  evento.target.value = '';
  if (!arquivos.length) return;
  emit('arquivos', { arquivos, comoDocumento: SELETORES[tipo].comoDocumento });
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
      class="grid place-content-center size-11 rounded-full text-[#3B3B3B] dark:text-[#FAFAFA] hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#00A884]"
      :class="{ 'bg-[#0A0A0A]/10 dark:bg-white/10': aberto }"
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
      class="absolute bottom-full mb-2 ltr:left-0 rtl:right-0 z-30 w-max min-w-[176px] py-2 px-1.5 rounded-2xl bg-white dark:bg-[#242626] shadow-[0_2px_8px_rgba(0,0,0,0.16)] dark:shadow-[0_4px_24px_rgba(0,0,0,0.5)] dark:ring-1 dark:ring-white/10"
    >
      <template v-for="item in itens" :key="item.chave">
        <hr
          v-if="item.separado"
          class="my-1.5 mx-3 border-0 border-t border-[#0A0A0A]/10 dark:border-white/15"
          aria-hidden="true"
        />
        <button
          type="button"
          role="menuitem"
          class="flex items-center gap-3 w-full h-9 ps-2.5 pe-4 rounded-lg text-start text-[15px] whitespace-nowrap text-[#0A0A0A] dark:text-[#FAFAFA] hover:bg-[#F5F6F6] dark:hover:bg-white/5 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#0A0A0A] dark:focus-visible:ring-[#FAFAFA]"
          :data-item="item.tipo"
          @click="escolher(item)"
        >
          <Icon
            :icon="item.icone"
            class="size-5 flex-shrink-0"
            :class="item.cor"
          />
          {{ t(`CONVERSA_CANAL.MAIS.${item.chave}`) }}
        </button>
      </template>
    </div>
    <input
      v-for="(seletor, tipo) in SELETORES"
      :key="tipo"
      :ref="guardarSeletor(tipo)"
      type="file"
      multiple
      :accept="seletor.filtro"
      class="hidden"
      tabindex="-1"
      aria-hidden="true"
      :data-seletor="tipo"
      @change="evento => escolheuArquivos(tipo, evento)"
    />
    <JanelaDoMais
      ref="janela"
      :inbox-id="caixa.id"
      :vira-texto="viraTexto"
      :enquete-em-texto="enquete === ENQUETE.TEXTO"
      :enviar="enviar"
      @fechou="botaoRef?.focus()"
    />
  </div>
</template>
