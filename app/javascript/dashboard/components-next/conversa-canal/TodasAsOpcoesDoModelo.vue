<script setup>
// Modelo com mais de 3 botões (#1702), como no app: o balão mostra os 2 primeiros e a
// linha "Ver todas as opções", que abre a janela presa à esquerda da conversa, a
// mesma da lista de opções (OpcoesDoWhatsapp), com todos os botões. O de link continua
// abrindo o endereço; os outros só mostram. Daqui não sai mensagem nenhuma.
// Fora da conversa (sem `.conversation-panel` acima), a janela abre ali mesmo, embaixo
// do botão, como a lista de contatos (ContatosDoWhatsapp).
import { nextTick, ref, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import BotaoDoModelo from './BotaoDoModelo.vue';

defineProps({
  // [{ tipo, texto, icone, endereco }] (useModeloDaMensagem).
  botoes: { type: Array, required: true },
  // A linha do balão, a mesma dos botões que aparecem.
  classe: { type: String, required: true },
});

const { t } = useI18n();
const abrir = useTemplateRef('abrir');
const fechar = useTemplateRef('fechar');
const janela = useTemplateRef('janela');
const alvo = ref(null);
const aberta = ref(false);

const abrirJanela = async () => {
  alvo.value =
    abrir.value?.closest('.conversation-panel')?.parentElement || null;
  aberta.value = true;
  await nextTick();
  fechar.value?.focus();
};
// Ao fechar, o foco volta para "Ver todas as opções", de onde a pessoa saiu.
const fecharJanela = async () => {
  aberta.value = false;
  await nextTick();
  abrir.value?.focus();
};
// A janela é modal: o Tab anda só entre o fechar e os links dela.
const prenderFoco = evento => {
  const itens = [...(janela.value?.querySelectorAll('a[href], button') || [])];
  if (!itens.length) return;
  const passo = evento.shiftKey ? -1 : 1;
  const atual = itens.indexOf(document.activeElement);
  itens[(atual + passo + itens.length) % itens.length].focus();
};

const LINHA_DA_JANELA =
  'flex items-center gap-4 min-h-14 px-3 py-3 rounded-[10px] text-[16px] text-[#1A6B42] dark:text-[#6FD07E] hover:bg-[#F4F2F3] dark:hover:bg-white/5';
</script>

<template>
  <button
    ref="abrir"
    type="button"
    :class="classe"
    class="hover:bg-[#0A0A0A]/5 dark:hover:bg-white/5"
    aria-haspopup="dialog"
    :aria-expanded="aberta"
    data-ver-todas-as-opcoes
    @click="abrirJanela"
  >
    <Icon icon="i-ph-list-bullets" class="size-5 flex-shrink-0" />
    {{ t('CONVERSA_CANAL.MODELO.VER_TODAS') }}
  </button>

  <Teleport v-if="aberta" :to="alvo || 'body'" :disabled="!alvo">
    <div
      v-if="alvo"
      class="absolute inset-0 z-40 bg-[#000]/35"
      data-fundo-das-opcoes
      @click="fecharJanela"
    />
    <div
      ref="janela"
      role="dialog"
      aria-modal="true"
      :aria-label="t('CONVERSA_CANAL.MODELO.TODAS_AS_OPCOES')"
      class="flex flex-col overflow-hidden bg-white dark:bg-[#242626]"
      :class="
        alvo
          ? 'absolute z-50 top-3 bottom-3 ltr:left-3 rtl:right-3 w-[417px] max-w-[calc(100%-24px)] rounded-[24px] shadow-[0_4px_24px_rgba(0,0,0,0.2)]'
          : 'w-full mt-2 rounded-lg'
      "
      data-janela-das-opcoes
      @keydown.esc="fecharJanela"
      @keydown.tab.prevent="prenderFoco"
    >
      <div class="flex items-center gap-6 h-16 px-6 flex-shrink-0">
        <button
          ref="fechar"
          type="button"
          class="grid place-content-center size-10 -ms-2 rounded-full text-[#0A0A0A] dark:text-[#FAFAFA] hover:bg-[#000]/5 dark:hover:bg-white/5"
          :aria-label="t('CONVERSA_CANAL.MODELO.FECHAR')"
          @click="fecharJanela"
        >
          <Icon icon="i-ph-x" class="size-6" />
        </button>
        <span class="text-[16px] text-[#0A0A0A] dark:text-[#FAFAFA]">
          {{ t('CONVERSA_CANAL.MODELO.TODAS_AS_OPCOES') }}
        </span>
      </div>
      <ul class="flex-1 overflow-y-auto px-3 pb-4">
        <li v-for="(botao, indice) in botoes" :key="indice">
          <BotaoDoModelo :botao="botao" :classe="LINHA_DA_JANELA" />
        </li>
      </ul>
    </div>
  </Teleport>
</template>
