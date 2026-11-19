<script setup>
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { ABA_SEGUROS } from '../../../fonte/gruposDeSeguros';
import LinkDeVolta from '../../ficha/LinkDeVolta.vue';

// #3057 — o caminho de volta de "Como trazer", "Trazer por PDFs" e "Do Agger":
// o mesmo link discreto de "Ajustar renovações" (‹ Seguros), que leva à aba
// Seguros (`?aba=seguros`), de onde se chega a essas telas. Sem ele, no celular
// a única saída era o ☰.
const { t } = useI18n();
const router = useRouter();

const voltar = () =>
  router.push({ name: 'relationships_home', query: { aba: ABA_SEGUROS } });
</script>

<template>
  <LinkDeVolta
    :texto="t('RELACIONAMENTOS_CARTEIRA.VOLTAR.TEXTO')"
    :rotulo="t('RELACIONAMENTOS_CARTEIRA.VOLTAR.ROTULO')"
    @voltar="voltar"
  />
</template>
