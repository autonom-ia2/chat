// Conversa do Instagram com a cara do Direct (#2079, épico #1701). A tela da conversa
// (MessagesView) decide uma vez se a conversa aberta usa o visual novo (caixa Instagram
// + chave `conversa_instagram` da conta) e fornece o contexto à lista, às linhas e ao
// topo. Chave e contexto próprios, separados da pele do WhatsApp (que testa só "há
// pele") e do e-mail. Sem a chave, nada muda.
import { computed, inject, provide } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { BARRA_DA_RESPOSTA, LISTA, TOPO } from './visualInstagram';

const CHAVE = Symbol('conversaDoInstagram');
// A sequência (horários, grupos, "Visto") que a MessageList calcula para as linhas.
const CHAVE_SEQUENCIA = Symbol('sequenciaDoInstagram');

export const instagramNaCaixa = (caixa, ligada) =>
  Boolean(ligada && caixa?.channel_type === INBOX_TYPES.INSTAGRAM);

const SEM_INSTAGRAM = {
  ligado: computed(() => false),
  fuso: computed(() => undefined),
  contato: computed(() => null),
};

const useLigado = () => {
  const conversa = useMapGetter('getSelectedChat');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const { isCloudFeatureEnabled } = useAccount();
  return computed(() =>
    instagramNaCaixa(
      caixaPorId.value(conversa.value?.inbox_id),
      isCloudFeatureEnabled(FEATURE_FLAGS.CONVERSA_INSTAGRAM)
    )
  );
};

export const useConversaDoInstagram = () => {
  const conversa = useMapGetter('getSelectedChat');
  const { currentAccount } = useAccount();
  const ligado = useLigado();

  const contexto = {
    ligado,
    fuso: computed(() => fusoDaConta(currentAccount.value)),
    contato: computed(() => conversa.value?.meta?.sender || null),
  };
  provide(CHAVE, contexto);

  return {
    ...contexto,
    classesDaLista: computed(() => (ligado.value ? LISTA : '')),
    classesDaBarra: computed(() => (ligado.value ? BARRA_DA_RESPOSTA : '')),
  };
};

// Lista, linhas e caixa de resposta perguntam aqui. Fora da conversa do Instagram: desligado.
export const useInstagramDaConversa = () => inject(CHAVE, SEM_INSTAGRAM);

// O topo da conversa (fora da MessagesView) só pergunta se é Instagram.
export const useTopoDoInstagram = () => {
  const ligado = useLigado();
  return computed(() => (ligado.value ? TOPO : ''));
};

export const fornecerSequencia = sequencia =>
  provide(CHAVE_SEQUENCIA, sequencia);
export const useSequenciaDoInstagram = () =>
  inject(
    CHAVE_SEQUENCIA,
    computed(() => new Map())
  );
