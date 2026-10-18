<script setup>
// O encaminhar na tela da conversa (#1702): a barra do modo seleção (no lugar do
// campo de digitar) e a janela "Encaminhar mensagem para". Esc na conversa (lista,
// barra ou nada focado) sai do modo seleção; trocar de conversa limpa tudo. Quem esconde a caixa de resposta é a
// tela da conversa, lendo `selecao.ativa`.
import { onBeforeUnmount, onMounted, watch } from 'vue';
import BarraDeEncaminhar from './BarraDeEncaminhar.vue';
import JanelaDeEncaminhar from './JanelaDeEncaminhar.vue';
import {
  abrirJanela,
  fecharJanela,
  sairDaSelecao,
  selecao,
} from './selecaoParaEncaminhar';

const props = defineProps({
  conversationId: { type: Number, required: true },
});

watch(
  () => props.conversationId,
  () => sairDaSelecao()
);

// A tela da conversa marca a sua área com este atributo (MessagesView).
const AREA_DA_CONVERSA = '[data-conversa-da-pele]';
// Quem tem Esc próprio (janela, menu, lista de escolha) fecha primeiro.
const ESC_DE_OUTRO = '[role="dialog"], [role="menu"], [role="listbox"]';

const escNaConversa = alvo =>
  alvo === document.body ||
  (Boolean(alvo?.closest?.(AREA_DA_CONVERSA)) && !alvo.closest(ESC_DE_OUTRO));

// Ouve na subida do evento, sem segurar: quem tratou o Esc antes (e parou ou
// marcou o evento) fica com ele; fora da conversa, o Esc não é nosso.
const aoTeclar = evento => {
  if (evento.key !== 'Escape' || evento.defaultPrevented) return;
  if (!selecao.ativa || selecao.janelaAberta) return;
  if (!escNaConversa(evento.target)) return;
  sairDaSelecao();
};

onMounted(() => document.addEventListener('keydown', aoTeclar));
onBeforeUnmount(() => {
  document.removeEventListener('keydown', aoTeclar);
  sairDaSelecao();
});
</script>

<template>
  <BarraDeEncaminhar
    v-if="selecao.ativa && selecao.conversaId === conversationId"
    :quantidade="selecao.ids.length"
    @sair="sairDaSelecao"
    @encaminhar="abrirJanela"
  />
  <JanelaDeEncaminhar
    v-if="selecao.janelaAberta && selecao.conversaId === conversationId"
    :conversation-id="conversationId"
    :message-ids="[...selecao.ids]"
    @fechar="fecharJanela"
    @enviado="sairDaSelecao"
  />
</template>
