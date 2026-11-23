<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import MessageList from 'dashboard/components-next/message/MessageList.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import AvisoDasAntigas from './AvisoDasAntigas.vue';
import { usePeleDaConversa } from 'dashboard/components-next/conversa-canal/usePeleDaConversa';
import { useConversaDeEmail } from 'dashboard/components-next/conversa-canal/email/useConversaDeEmail';
import { useConversaDoInstagram } from 'dashboard/components-next/conversa-canal/instagram/useConversaDoInstagram';

// #3165 — a lista de mensagens do painel, com a mesma pele do canal (WhatsApp, e-mail
// como o Gmail, Instagram como o Direct; os outros canais no visual de sempre). Fica
// dentro do VisorDaConversa, que fornece a conversa: as peles leem essa, não a aberta.
// Rola sozinha; ao chegar no começo da conversa, puxa as mensagens antigas.
const props = defineProps({
  mensagens: { type: Array, required: true },
  caixaId: { type: Number, default: null },
  temAntigas: { type: Boolean, default: false },
  carregandoAntigas: { type: Boolean, default: false },
  erroAntigas: { type: Boolean, default: false },
  carregarAntigas: { type: Function, required: true },
});

const { t } = useI18n();
const usuarioId = useMapGetter('getCurrentUserID');
const caixaPorId = useMapGetter('inboxes/getInbox');
const ehEmail = computed(
  () => caixaPorId.value(props.caixaId)?.channel_type === INBOX_TYPES.EMAIL
);

const { classesDaLista } = usePeleDaConversa();
const { ligado: emailNovo, classesDaLista: classesDoEmail } =
  useConversaDeEmail();
const { classesDaLista: classesDoInstagram } = useConversaDoInstagram();

// No e-mail novo o mais recente fica no topo (como no painel): as antigas ficam no fim.
const lista = ref(null);
const painel = () => lista.value?.$el;
const BORDA = 80;

const irParaAsRecentes = async () => {
  await nextTick();
  const el = painel();
  if (!el) return;
  el.scrollTop = emailNovo.value ? 0 : el.scrollHeight;
};

const puxarAntigas = async () => {
  const el = painel();
  if (!el) return;
  const alturaAntes = el.scrollHeight;
  const topoAntes = el.scrollTop;
  const vieram = await props.carregarAntigas();
  if (!vieram || emailNovo.value) return;
  await nextTick();
  // As antigas entram em cima: a mensagem que a pessoa lia continua no lugar.
  el.scrollTop = topoAntes + (el.scrollHeight - alturaAntes);
};

const aoRolar = () => {
  const el = painel();
  // Depois de uma falha, só tenta de novo pelo botão (rolar não repete o pedido).
  if (
    !el ||
    !props.temAntigas ||
    props.carregandoAntigas ||
    props.erroAntigas
  ) {
    return;
  }
  const naBorda = emailNovo.value
    ? el.scrollHeight - el.scrollTop - el.clientHeight < BORDA
    : el.scrollTop < BORDA;
  if (naBorda) puxarAntigas();
};

// Conversa nova (a primeira leva de mensagens): abre nas mais recentes.
watch(
  () => props.mensagens.length > 0 && props.mensagens.at(-1)?.id,
  (agora, antes) => {
    if (agora && !antes) irParaAsRecentes();
  },
  { immediate: true }
);
</script>

<template>
  <MessageList
    ref="lista"
    data-visor-lista
    class="conversation-panel m-0 flex h-full min-h-0 flex-col overflow-y-auto pb-4 outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-n-brand"
    :class="[classesDaLista, classesDoEmail, classesDoInstagram]"
    tabindex="0"
    :aria-label="t('CRM_CARD.CONVERSAS.VISOR.MENSAGENS')"
    :current-user-id="usuarioId"
    :is-an-email-channel="ehEmail"
    :messages="mensagens"
    @scroll.passive="aoRolar"
  >
    <template #beforeAll>
      <li
        v-if="carregandoAntigas && !emailNovo"
        class="flex min-h-16 list-none items-center justify-center first:mt-auto"
        role="status"
      >
        <Spinner class="text-n-brand" />
        <span class="sr-only">
          {{ t('CRM_CARD.CONVERSAS.VISOR.CARREGANDO_ANTIGAS') }}
        </span>
      </li>
      <AvisoDasAntigas
        v-else-if="erroAntigas && !emailNovo"
        class="first:mt-auto"
        @tentar="puxarAntigas"
      />
      <li
        v-else-if="!emailNovo"
        class="list-none first:mt-auto"
        aria-hidden="true"
      />
    </template>
    <template #after>
      <li
        v-if="carregandoAntigas && emailNovo"
        class="flex min-h-16 list-none items-center justify-center"
        role="status"
      >
        <Spinner class="text-n-brand" />
        <span class="sr-only">
          {{ t('CRM_CARD.CONVERSAS.VISOR.CARREGANDO_ANTIGAS') }}
        </span>
      </li>
      <AvisoDasAntigas
        v-else-if="erroAntigas && emailNovo"
        @tentar="puxarAntigas"
      />
    </template>
  </MessageList>
</template>
