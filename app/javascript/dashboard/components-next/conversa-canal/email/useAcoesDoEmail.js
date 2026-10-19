// Ações do menu ⋮ de cada e-mail (#1786), adaptadas do Gmail: traduzir, copiar o link,
// imprimir só este e-mail, marcar a conversa como não lida e excluir. Usam as mesmas
// ações do menu de contexto do Chatwoot (store e API de sempre), sem rota nova.
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert, useTrack } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useConversationRoutePath } from 'dashboard/composables/useConversationRoutePath';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { conversationUrl, frontendURL } from 'dashboard/helper/URLHelper';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import { CONVERSATION_EVENTS } from 'dashboard/helper/AnalyticsHelper/events';
import MessageApi from 'dashboard/api/inbox/message';
import { CSP_DO_EMAIL } from './documentoDoEmail';

// Folha de impressão: só o e-mail, letra legível, sem o painel em volta.
const ESTILO_DA_IMPRESSAO = `
  body { font: 14px/1.5 -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif; color: #1f1f1f; margin: 32px; }
  h1 { font-size: 20px; font-weight: 600; margin: 0 0 16px; }
  dl { display: grid; grid-template-columns: auto 1fr; gap: 2px 12px; margin: 0 0 20px; padding-bottom: 12px; border-bottom: 1px solid #ddd; font-size: 12px; }
  dt { color: #5f6368; text-align: end; }
  dd { margin: 0; }
  img { max-width: 100%; }
  blockquote { margin: 0 0 0 .8ex; border-left: 1px solid #ccc; padding-left: 1ex; }
`;

const TRADUZINDO_NO_SERVIDOR = 202;
const PRAZO_DA_TRADUCAO = 120000;

const escapar = texto => {
  const div = document.createElement('div');
  div.textContent = String(texto ?? '');
  return div.innerHTML;
};

export const useAcoesDoEmail = ({ conversationId, messageId }) => {
  const { t } = useI18n();
  const store = useStore();
  const router = useRouter();
  const { uiSettings } = useUISettings();
  const { buildConversationListPath } = useConversationRoutePath();
  const contaAtual = useMapGetter('getCurrentAccountId');
  const contaPorId = useMapGetter('accounts/getAccount');

  // Põe a tradução na mensagem do painel na hora, sem esperar o aviso em tempo real
  // (que pode atrasar ou não vir): o cartão troca para o texto traduzido.
  const mensagemNaTela = () =>
    store.getters.getSelectedChat?.messages?.find(
      m => m.id === messageId.value
    );

  const guardarTraducao = (idioma, conteudo) => {
    const mensagem = mensagemNaTela();
    if (!mensagem) return;
    const atributos = mensagem.content_attributes || {};
    store.dispatch('updateMessage', {
      ...mensagem,
      content_attributes: {
        ...atributos,
        translations: { ...(atributos.translations || {}), [idioma]: conteudo },
      },
    });
  };

  // Sem o Google, a IA da conta traduz num job (202): a tradução chega pelo aviso em
  // tempo real (message.updated). Se não chegar no prazo, avisa que não deu.
  const esperarTraducao = idioma => {
    useAlert(t('CONVERSA_CANAL.EMAIL.TRADUZINDO'));
    setTimeout(() => {
      const mensagem = mensagemNaTela();
      if (mensagem && !mensagem.content_attributes?.translations?.[idioma]) {
        useAlert(t('CONVERSA_CANAL.EMAIL.TRADUCAO_FALHOU'));
      }
    }, PRAZO_DA_TRADUCAO);
  };

  const traduzir = async () => {
    const idiomaDaConta = contaPorId.value(contaAtual.value)?.locale;
    const idioma = uiSettings.value?.locale || idiomaDaConta || 'en';
    try {
      // Resposta `{ content: null }` = o tradutor não devolveu nada: avisa.
      const { data, status } = await MessageApi.translateMessage(
        conversationId.value,
        messageId.value,
        idioma
      );
      useTrack(CONVERSATION_EVENTS.TRANSLATE_A_MESSAGE);
      if (status === TRADUZINDO_NO_SERVIDOR) {
        esperarTraducao(idioma);
        return;
      }
      if (data?.content) guardarTraducao(idioma, data.content);
      else if (data && typeof data === 'object') {
        useAlert(t('CONVERSA_CANAL.EMAIL.TRADUCAO_FALHOU'));
      }
    } catch (error) {
      useAlert(parseAPIErrorResponse(error));
    }
  };

  const copiarLink = async () => {
    const endereco =
      window.chatwootConfig.hostURL +
      frontendURL(
        conversationUrl({
          id: conversationId.value,
          accountId: contaAtual.value,
        })
      );
    await copyTextToClipboard(`${endereco}?messageId=${messageId.value}`);
    useAlert(t('CONVERSATION.CONTEXT_MENU.LINK_COPIED'));
  };

  // Imprime numa moldura escondida, sem script (sandbox), com o corpo já limpo que
  // está na tela. `linhas` são pares [rótulo, valor] do cabeçalho.
  const imprimir = ({ assunto, linhas, corpoHtml }) => {
    const moldura = document.createElement('iframe');
    moldura.setAttribute('sandbox', 'allow-same-origin allow-modals');
    moldura.setAttribute('aria-hidden', 'true');
    moldura.setAttribute('referrerpolicy', 'no-referrer');
    moldura.className = 'fixed size-0 border-0 opacity-0 pointer-events-none';
    const cabecalho = linhas
      .filter(([, valor]) => valor)
      .map(
        ([rotulo, valor]) =>
          `<dt>${escapar(rotulo)}</dt><dd>${escapar(valor)}</dd>`
      )
      .join('');
    moldura.srcdoc = `<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${CSP_DO_EMAIL}"><meta name="referrer" content="no-referrer"><title>${escapar(
      assunto
    )}</title><style>${ESTILO_DA_IMPRESSAO}</style></head><body><h1>${escapar(
      assunto
    )}</h1><dl>${cabecalho}</dl>${corpoHtml}</body></html>`;
    moldura.onload = () => {
      moldura.contentWindow.focus();
      moldura.contentWindow.print();
      setTimeout(() => moldura.remove(), 1000);
    };
    document.body.appendChild(moldura);
  };

  // Vale para a conversa inteira (a API não marca a partir de um e-mail); volta à lista.
  const marcarComoNaoLida = async () => {
    try {
      await store.dispatch('markMessagesUnread', { id: conversationId.value });
      router.push(buildConversationListPath());
    } catch (error) {
      useAlert(parseAPIErrorResponse(error));
    }
  };

  const excluir = async () => {
    try {
      await store.dispatch('deleteMessage', {
        conversationId: conversationId.value,
        messageId: messageId.value,
      });
      useAlert(t('CONVERSATION.SUCCESS_DELETE_MESSAGE'));
    } catch {
      useAlert(t('CONVERSATION.FAIL_DELETE_MESSSAGE'));
    }
  };

  return { traduzir, copiarLink, imprimir, marcarComoNaoLida, excluir };
};
