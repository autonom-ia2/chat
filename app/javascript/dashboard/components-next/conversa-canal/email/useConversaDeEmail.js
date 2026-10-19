// Conversa de e-mail com a cara do Gmail (#1786, épico #1701). A tela da conversa
// (MessagesView) decide uma vez se a conversa aberta usa o visual novo (caixa de
// e-mail + chave `conversa_email_nova` da conta) e fornece o contexto aos cartões, ao
// topo e às ações. Chave própria, separada da pele do WhatsApp: os componentes do
// WhatsApp testam só "há pele", e o e-mail não pode herdar o visual deles.
// Sem a chave, nada é fornecido e a conversa de e-mail é a de sempre.
import { computed, inject, provide, ref, watch } from 'vue';
import { useEmitter } from 'dashboard/composables/emitter';
import { useEventListener } from '@vueuse/core';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useMapGetter } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { useCanOperateConversation } from 'dashboard/composables/useCanOperateConversation';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { fusoDaConta } from 'dashboard/helper/fusoDaConta';
import {
  FORMATACAO_FIXA,
  REGUA_SO_NO_AA,
  LISTA_DO_EMAIL,
  RESPOSTA_DO_EMAIL,
  RESPOSTA_EXPANDIDA,
  RESPOSTA_EM_JANELA,
} from './visualEmail';
import { assuntoDaConversa, ehEmail } from './dadosDoEmail';

// Evento das ações do fim da conversa para a caixa de resposta.
export const RESPONDER_EMAIL = 'conversaCanal:responderEmail';
export const MODOS_DE_RESPOSTA = {
  RESPONDER: 'responder',
  TODOS: 'todos',
  ENCAMINHAR: 'encaminhar',
  NOTA: 'nota',
};
// Tamanho da caixa de resposta: embaixo da conversa, ocupando a conversa ou em janela.
export const TAMANHOS = {
  NORMAL: 'normal',
  EXPANDIDA: 'expandida',
  JANELA: 'janela',
};
// Pedidos da caixa de resposta do e-mail para o ReplyBox: descartar e pôr uma resposta
// pronta no texto (leva o conteúdo).
export const DESCARTAR_EMAIL = 'conversaCanal:descartarEmail';
export const MODELOS_DO_EMAIL = 'conversaCanal:modelosDoEmail';
// Modelo de e-mail das Campanhas escolhido no "+" (leva o id).
export const MODELO_DE_CAMPANHA = 'conversaCanal:modeloDeCampanha';

const CHAVE = Symbol('conversaDeEmail');
// As conversas anterior e seguinte do contato, que o MessagesView já busca (EmailsVizinhos).
export const CONVERSAS_DO_CONTATO = Symbol('conversasDoContato');
// Escolha de cada atendente (Rodrigo, 17/10): por padrão as mensagens antigas ficam
// abertas; recolher é opção.
const RECOLHER = 'conversa_email_recolher_antigas';

export const emailNovoNaCaixa = (caixa, ligada) =>
  Boolean(ligada && caixa?.channel_type === INBOX_TYPES.EMAIL);

const SEM_EMAIL = {
  ligado: computed(() => false),
  recolher: computed(() => false),
  alternarRecolher: () => {},
  fuso: computed(() => undefined),
  assunto: computed(() => ''),
  ultimoEmailId: computed(() => null),
  respostaAberta: computed(() => false),
  fecharResposta: () => {},
  tamanho: computed(() => TAMANHOS.NORMAL),
  alternarTamanho: () => {},
  formatacao: computed(() => false),
  alternarFormatacao: () => {},
  podeOperar: computed(() => true),
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
  const assunto = computed(() =>
    assuntoDaConversa({ conversa: conversa.value, emails: emails.value })
  );

  // Como no leitor de e-mail (Rodrigo, 18/10): a caixa de resposta só aparece quando
  // o atendente aperta Responder, Responder a todos, Encaminhar ou Nota privada; fecha
  // depois do envio, ao trocar de conversa ou no "Fechar". O rascunho continua
  // guardado pelo Chatwoot.
  const respostaAberta = ref(false);
  const tamanho = ref(TAMANHOS.NORMAL);
  const formatacao = ref(false);
  const fecharResposta = () => {
    respostaAberta.value = false;
    tamanho.value = TAMANHOS.NORMAL;
  };
  // Aumentar e Janela alternam: apertar de novo volta ao tamanho normal.
  const alternarTamanho = novo => {
    tamanho.value = tamanho.value === novo ? TAMANHOS.NORMAL : novo;
  };
  const alternarFormatacao = () => {
    formatacao.value = !formatacao.value;
  };
  // Esc fecha a caixa (o rascunho fica), menos quando um menu ou lista está aberto.
  useEventListener(document, 'keydown', evento => {
    if (evento.key !== 'Escape' || !respostaAberta.value) return;
    if (document.querySelector('[role=menu], [role=listbox]')) return;
    if (!document.activeElement?.closest('.reply-box')) return;
    fecharResposta();
  });
  useEmitter(RESPONDER_EMAIL, () => {
    respostaAberta.value = true;
  });
  useEmitter(BUS_EVENTS.MESSAGE_SENT, fecharResposta);
  watch(() => conversa.value?.id, fecharResposta);

  // Quem só lê a conversa (conversation_view, #1800) não vê Responder, Encaminhar, Nota,
  // Spam, Lixeira nem Excluir: a mesma regra da main (o servidor recusa do mesmo jeito).
  const podeOperar = useCanOperateConversation(conversa);

  const contexto = {
    ligado,
    podeOperar,
    respostaAberta,
    fecharResposta,
    tamanho,
    alternarTamanho,
    formatacao,
    alternarFormatacao,
    recolher,
    alternarRecolher,
    fuso: computed(() => fusoDaConta(currentAccount.value)),
    assunto,
    ultimoEmailId: computed(() => emails.value.at(-1)?.id ?? null),
  };
  provide(CHAVE, contexto);

  return {
    ...contexto,
    classesDaLista: computed(() => {
      if (!ligado.value) return '';
      // Expandida: a resposta ocupa o lugar da conversa.
      const expandida =
        respostaAberta.value && tamanho.value === TAMANHOS.EXPANDIDA;
      return expandida ? `${LISTA_DO_EMAIL} !hidden` : LISTA_DO_EMAIL;
    }),
    classesDaBarra: computed(() => {
      if (!ligado.value) return '';
      if (!respostaAberta.value) return '!hidden';
      return [
        RESPOSTA_DO_EMAIL,
        tamanho.value === TAMANHOS.EXPANDIDA ? RESPOSTA_EXPANDIDA : '',
        tamanho.value === TAMANHOS.JANELA ? RESPOSTA_EM_JANELA : '',
        // Régua só com o "Aa": sem ele, a barra flutuante não cobre o texto selecionado.
        formatacao.value ? FORMATACAO_FIXA : REGUA_SO_NO_AA,
      ].join(' ');
    }),
  };
};

// Cartões, topo e ações perguntam aqui. Fora da conversa de e-mail nova: desligado.
export const useEmailDaConversa = () => inject(CHAVE, SEM_EMAIL);
