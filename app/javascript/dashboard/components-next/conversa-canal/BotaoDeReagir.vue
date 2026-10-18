<script setup>
// O botão de reagir ao lado do balão (#1702), como no WhatsApp Web: aparece ao
// passar o mouse, abre a barra com 6 emojis e o "+" do seletor completo. Também
// abre pelo "Reagir" do menu da mensagem. Teclado: setas andam na barra, Esc fecha
// e o foco volta para o botão.
import {
  defineAsyncComponent,
  nextTick,
  onBeforeUnmount,
  ref,
  watch,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';
import Icon from 'next/icon/Icon.vue';
import { emitter } from 'shared/helpers/mitt';
import { ORIENTATION } from '../message/constants';
import {
  ABRIR_REACOES,
  REACOES_RAPIDAS,
  proximoIndice,
} from './reacaoDoAtendente';

const props = defineProps({
  mensagemId: { type: Number, required: true },
  lado: { type: String, default: ORIENTATION.LEFT },
  atual: { type: String, default: '' },
  bloqueado: { type: Boolean, default: false },
  enviando: { type: Boolean, default: false },
});

const emit = defineEmits(['reagir']);

const EmojiIconPicker = defineAsyncComponent(
  () =>
    import('dashboard/components-next/emoji-icon-picker/EmojiIconPicker.vue')
);

const { t } = useI18n();
const aberta = ref(false);
const seletor = ref(false);
const gatilho = ref(null);
const barra = ref(null);
const seletorCompleto = ref(null);

// Primeiro controle do seletor completo (a busca de emoji).
const FOCAVEL_DO_SELETOR = 'input, button';

const botoesDaBarra = () =>
  Array.from(barra.value?.querySelectorAll('button') || []);

const abrir = async () => {
  if (props.bloqueado) return;
  aberta.value = true;
  seletor.value = false;
  await nextTick();
  const botoes = botoesDaBarra();
  const indice = Math.max(REACOES_RAPIDAS.indexOf(props.atual), 0);
  botoes[indice]?.focus();
};

const fechar = ({ devolverFoco = true } = {}) => {
  if (!aberta.value) return;
  aberta.value = false;
  seletor.value = false;
  if (devolverFoco) gatilho.value?.focus();
};

const alternar = () => (aberta.value ? fechar() : abrir());

// O "+" troca a barra pelo seletor completo. A barra some com o foco dentro, então o
// foco espera no botão de reagir e vai para o seletor assim que ele montar (o seletor
// é carregado na hora, por isso o watch na referência, e não um nextTick só).
const abrirSeletor = () => {
  gatilho.value?.focus();
  seletor.value = true;
};

watch(seletorCompleto, async instancia => {
  if (!instancia) return;
  await nextTick();
  instancia.$el?.querySelector?.(FOCAVEL_DO_SELETOR)?.focus();
});

const escolher = emoji => {
  emit('reagir', emoji);
  fechar();
};

const navegar = evento => {
  const botoes = botoesDaBarra();
  const atual = botoes.indexOf(document.activeElement);
  const proximo = proximoIndice(evento.key, atual, botoes.length);
  if (proximo === null) return;
  evento.preventDefault();
  botoes[proximo]?.focus();
};

const abrirPeloMenu = ({ messageId }) => {
  if (messageId === props.mensagemId) abrir();
};
emitter.on(ABRIR_REACOES, abrirPeloMenu);
onBeforeUnmount(() => emitter.off(ABRIR_REACOES, abrirPeloMenu));
</script>

<template>
  <div
    v-on-click-outside="() => fechar({ devolverFoco: false })"
    class="relative self-center shrink-0"
    :class="lado === ORIENTATION.RIGHT ? 'order-first' : ''"
    data-reagir-do-balao
    @keydown.esc.stop="fechar()"
  >
    <button
      ref="gatilho"
      v-tooltip.top="
        bloqueado ? t('CONVERSA_CANAL.REAGIR.FORA_DA_JANELA') : null
      "
      type="button"
      class="grid place-content-center size-11 rounded-full text-[#8C8C8C] dark:text-[#A7A8A8] transition-opacity opacity-0 group-hover/linha:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:hidden"
      :class="[
        aberta ? '!opacity-100' : '',
        bloqueado ? 'cursor-not-allowed' : 'hover:text-[#54656F]',
      ]"
      :aria-label="t('CONVERSA_CANAL.REAGIR.BOTAO')"
      :aria-disabled="bloqueado"
      :aria-expanded="aberta"
      aria-haspopup="true"
      @click="alternar"
    >
      <!-- O círculo do app tem 32 px; a área de toque, 44 px. -->
      <span
        class="grid place-content-center size-8 rounded-full bg-white/80 dark:bg-[#242626]/80 shadow-[0_1px_1px_rgba(11,20,26,0.13)]"
      >
        <Icon icon="i-ph-smiley" class="size-5" />
      </span>
    </button>
    <div
      v-if="aberta && !seletor"
      ref="barra"
      role="toolbar"
      :aria-label="t('CONVERSA_CANAL.REAGIR.BARRA')"
      class="absolute bottom-full mb-1 z-20 flex items-center gap-0.5 p-1 rounded-full bg-white dark:bg-[#242626] shadow-[0_2px_5px_rgba(11,20,26,0.26)]"
      :class="
        lado === ORIENTATION.RIGHT
          ? 'ltr:right-0 rtl:left-0'
          : 'ltr:left-0 rtl:right-0'
      "
      @keydown="navegar"
    >
      <button
        v-for="emoji in REACOES_RAPIDAS"
        :key="emoji"
        type="button"
        class="grid place-content-center size-11 rounded-full text-[24px] leading-none transition-transform hover:scale-110 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#1DAA61]"
        :class="emoji === atual ? 'bg-[#000]/10 dark:bg-white/15' : ''"
        :aria-label="
          emoji === atual
            ? t('CONVERSA_CANAL.REAGIR.TIRAR', { emoji })
            : t('CONVERSA_CANAL.REAGIR.COM', { emoji })
        "
        :aria-pressed="emoji === atual"
        :disabled="enviando"
        @click="escolher(emoji)"
      >
        {{ emoji }}
      </button>
      <button
        type="button"
        class="grid place-content-center size-11 rounded-full text-[#54656F] dark:text-[#A7A8A8] bg-[#000]/5 dark:bg-white/10 focus-visible:outline focus-visible:outline-2 focus-visible:outline-[#1DAA61]"
        :aria-label="t('CONVERSA_CANAL.REAGIR.MAIS')"
        :disabled="enviando"
        @click="abrirSeletor"
      >
        <Icon icon="i-ph-plus" class="size-5" />
      </button>
    </div>
    <EmojiIconPicker
      v-if="aberta && seletor"
      ref="seletorCompleto"
      mode="emoji"
      class="bottom-full mb-1"
      :class="
        lado === ORIENTATION.RIGHT
          ? 'ltr:right-0 rtl:left-0'
          : 'ltr:left-0 rtl:right-0'
      "
      @select="escolher($event.value)"
    />
  </div>
</template>
