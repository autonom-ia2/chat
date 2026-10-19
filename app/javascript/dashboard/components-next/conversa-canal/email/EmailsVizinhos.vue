<script setup>
// "E-mail anterior / seguinte deste contato" no resumo do topo (#1786). Substitui, só no
// e-mail novo, a pílula do Chatwoot que boiava no meio da tela, com a data em inglês.
// As vizinhas vêm do MessagesView (useContactConversationNavigation), que já as busca:
// aqui só se lê, para não pedir de novo ao servidor.
import { computed, inject } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';
import { useAgora } from '../useAgora';
import { idiomaDoPainel } from '../dataDaConversa';
import { dataCurtaDoEmail } from './dadosDoEmail';
import { CONVERSAS_DO_CONTATO, useEmailDaConversa } from './useConversaDeEmail';

const { t, locale } = useI18n();
const email = useEmailDaConversa();
const agora = useAgora();
const vizinhas = inject(CONVERSAS_DO_CONTATO, null);

const quando = conversa =>
  dataCurtaDoEmail({
    quando: conversa.created_at,
    agora: agora.value,
    fuso: email.fuso.value,
    idioma: idiomaDoPainel(locale.value),
  });

const links = computed(() => {
  if (!vizinhas) return [];
  return [
    {
      conversa: vizinhas.olderConversation.value,
      chave: 'EMAIL_ANTERIOR',
      icone: 'i-lucide-history',
    },
    {
      conversa: vizinhas.newerConversation.value,
      chave: 'EMAIL_SEGUINTE',
      icone: 'i-lucide-arrow-right',
    },
  ]
    .filter(link => link.conversa)
    .map(link => ({
      ...link,
      id: link.conversa.id,
      para: vizinhas.buildConversationPath(link.conversa.id),
      data: quando(link.conversa),
    }));
});
</script>

<template>
  <router-link
    v-for="link in links"
    :key="link.chave"
    :to="link.para"
    class="relative inline-flex items-center gap-1.5 h-6 px-2 -mx-1 rounded-md before:absolute before:inset-x-0 before:-inset-y-2.5 before:content-[''] text-xs text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
    :data-email-vizinho="link.chave"
  >
    <Icon :icon="link.icone" class="size-3.5 flex-shrink-0" />
    {{ t(`CONVERSA_CANAL.EMAIL.${link.chave}`, { data: link.data }) }}
  </router-link>
</template>
