// Conversa de e-mail com a cara do Gmail (#1786, épico #1701). A tela da conversa
// (MessagesView) decide uma vez se a conversa aberta usa o visual novo (caixa de
// e-mail + chave `conversa_email_nova` da conta) e fornece o contexto aos cartões, ao
// topo e às ações. Chave própria, separada da pele do WhatsApp: os componentes do
// WhatsApp testam só "há pele", e o e-mail não pode herdar o visual deles.
// Sem a chave, nada é fornecido e a conversa de e-mail é a de sempre.
import { computed, inject, provide } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import { MESSAGE_TYPES } from '../../message/constants';
import { LISTA_DO_EMAIL, RESPOSTA_DO_EMAIL } from './visualEmail';

const CHAVE = Symbol('conversaDeEmail');
// Escolha de cada atendente (Rodrigo, 17/10): por padrão as mensagens antigas ficam
// abertas; recolher é opção.
const RECOLHER = 'conversa_email_recolher_antigas';

export const emailNovoNaCaixa = (caixa, ligada) =>
  Boolean(ligada && caixa?.channel_type === INBOX_TYPES.EMAIL);

const ehEmail = mensagem =>
  !mensagem.private &&
  [MESSAGE_TYPES.INCOMING, MESSAGE_TYPES.OUTGOING].includes(
    mensagem.message_type
  );

const SEM_EMAIL = {
  ligado: computed(() => false),
  recolher: computed(() => false),
  alternarRecolher: () => {},
  fuso: computed(() => undefined),
  assunto: computed(() => ''),
  ultimoEmailId: computed(() => null),
};

export const useConversaDeEmail = () => {
  const conversa = useMapGetter('getSelectedChat');
  const caixaPorId = useMapGetter('inboxes/getInbox');
  const { currentAccount, isCloudFeatureEnabled } = useAccount();
  const { uiSettings, updateUISettings } = useUISettings();

  const ligado = computed(() =>
    emailNovoNaCaixa(
      caixaPorId.value(conversa.value?.inbox_id),
      isCloudFeatureEnabled(FEATURE_FLAGS.CONVERSA_EMAIL_NOVA)
    )
  );
  const recolher = computed(() => Boolean(uiSettings.value?.[RECOLHER]));
  const alternarRecolher = () =>
    updateUISettings({ [RECOLHER]: !recolher.value });

  const emails = computed(() =>
    (conversa.value?.messages || []).filter(ehEmail)
  );
  const assunto = computed(
    () =>
      conversa.value?.additional_attributes?.mail_subject ||
      emails.value.find(m => m.content_attributes?.email?.subject)
        ?.content_attributes.email.subject ||
      ''
  );

  const contexto = {
    ligado,
    recolher,
    alternarRecolher,
    fuso: computed(() => fusoDaConta(currentAccount.value)),
    assunto,
    ultimoEmailId: computed(() => emails.value.at(-1)?.id ?? null),
  };
  provide(CHAVE, contexto);

  return {
    ...contexto,
    classesDaLista: computed(() => (ligado.value ? LISTA_DO_EMAIL : '')),
    classesDaBarra: computed(() => (ligado.value ? RESPOSTA_DO_EMAIL : '')),
  };
};

// Cartões, topo e ações perguntam aqui. Fora da conversa de e-mail nova: desligado.
export const useEmailDaConversa = () => inject(CHAVE, SEM_EMAIL);

// Evento das ações do fim da conversa para a caixa de resposta.
export const RESPONDER_EMAIL = 'conversaCanal:responderEmail';
export const MODOS_DE_RESPOSTA = {
  RESPONDER: 'responder',
  TODOS: 'todos',
  ENCAMINHAR: 'encaminhar',
};
