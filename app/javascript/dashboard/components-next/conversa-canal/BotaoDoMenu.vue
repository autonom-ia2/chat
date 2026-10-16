<script setup>
// A setinha ⌄ do canto do balão (#1702): aparece ao passar o mouse e abre o mesmo menu
// do clique direito (responder, copiar, baixar...), como no app.
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

const { t } = useI18n();

// O menu da mensagem abre pelo evento de clique direito, no ponto pedido.
const abrirMenu = evento => {
  const botao = evento.currentTarget;
  const caixa = botao.getBoundingClientRect();
  botao.dispatchEvent(
    new MouseEvent('contextmenu', {
      bubbles: true,
      cancelable: true,
      clientX: caixa.left,
      clientY: caixa.bottom,
    })
  );
};
</script>

<template>
  <button
    type="button"
    class="absolute top-[3px] ltr:right-[3px] rtl:left-[3px] z-[2] grid place-content-center w-8 h-6 rounded-[6px] bg-inherit text-[#8C8C8C] dark:text-[#A7A8A8] opacity-0 group-hover/balao:opacity-100 focus-visible:opacity-100 [@media(hover:none)]:hidden transition-opacity [[data-bubble-name=image]_&]:bg-transparent [[data-bubble-name=image]_&]:bg-gradient-to-bl [[data-bubble-name=image]_&]:from-[#000]/40 [[data-bubble-name=image]_&]:to-transparent [[data-bubble-name=image]_&]:text-white [[data-bubble-name=video]_&]:bg-transparent [[data-bubble-name=video]_&]:text-white"
    :aria-label="t('CONVERSA_CANAL.MIDIA.MENU')"
    data-menu-do-balao
    @click.stop="abrirMenu"
  >
    <Icon icon="i-ph-caret-down" class="size-5" />
  </button>
</template>
