import { computed, ref, watch } from 'vue';
import ConversationAPI from 'dashboard/api/inbox/conversation';
import MessageAPI from 'dashboard/api/inbox/message';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { useCaixaDeEmailNova } from 'dashboard/components-next/conversa-canal/email/caixaDeEmailNova';
import {
  assuntoDaConversa,
  ehEmail,
} from 'dashboard/components-next/conversa-canal/email/dadosDoEmail';
import {
  DESTINOS,
  chaveDaEscolha,
  conversaDeDestino,
  conversaDoCanal,
  conversaOculta,
  tipoAoContinuar,
} from './continuarConversa';

// #1505 — continuar a conversa que o contato já tem na caixa. Guarda a
// escolha ("Continuar" ou "Começar conversa nova") e pergunta ao servidor se
// a conversa aceita texto livre (`can_reply`). Trocar de contato ou de canal
// zera a escolha: o padrão volta a "Continuar".
export function useContinuarConversa({ contato, canal }) {
  const destino = ref(DESTINOS.CONTINUAR);
  const podeResponder = ref(false);
  // #1809 — conversa de e-mail: o assunto dela (a resposta sai com "Re: ...") e o
  // último e-mail, que vai como histórico no fim, como na resposta.
  const assunto = ref('');
  const ultimoEmail = ref(null);
  const ehCaixaDeEmailNova = useCaixaDeEmailNova();
  const carregando = ref(false);
  const erro = ref(false);

  const existente = computed(() => conversaDoCanal(canal.value));
  const oculta = computed(() => conversaOculta(canal.value));
  const conversa = computed(() =>
    conversaDeDestino({ canal: canal.value, destino: destino.value })
  );
  const tipo = computed(() =>
    conversa.value
      ? tipoAoContinuar({
          canal: canal.value,
          podeResponder: podeResponder.value,
        })
      : ''
  );
  // Enquanto não se sabe o que a conversa aceita, a mensagem não aparece e o
  // envio fica parado.
  const esperando = computed(
    () => Boolean(conversa.value) && (carregando.value || erro.value)
  );

  // Só o último pedido mexe no estado (mesmo cuidado da lista de canais).
  let ultimoPedido = 0;

  const carregar = async () => {
    ultimoPedido += 1;
    const pedido = ultimoPedido;
    const alvo = existente.value?.visible ? existente.value : null;
    podeResponder.value = false;
    assunto.value = '';
    ultimoEmail.value = null;
    erro.value = false;
    carregando.value = Boolean(alvo);
    if (!alvo) return;
    try {
      const email = canal.value?.channelType === INBOX_TYPES.EMAIL;
      // O histórico só existe na conversa de e-mail nova (chave conversa_email_nova).
      const comHistorico = email && ehCaixaDeEmailNova(canal.value?.id);
      // O histórico é extra: se as mensagens não vierem, o e-mail sai sem ele, mas sai.
      const [{ data }, mensagens] = await Promise.all([
        ConversationAPI.show(alvo.displayId),
        comHistorico
          ? MessageAPI.getPreviousMessages({
              conversationId: alvo.displayId,
            }).catch(() => null)
          : null,
      ]);
      if (pedido !== ultimoPedido) return;
      podeResponder.value = data?.can_reply === true;
      const emails = (mensagens?.data?.payload || []).filter(ehEmail);
      assunto.value = email
        ? assuntoDaConversa({ conversa: data, emails })
        : '';
      ultimoEmail.value = emails.at(-1) || null;
    } catch (error) {
      if (pedido === ultimoPedido) erro.value = true;
    } finally {
      if (pedido === ultimoPedido) carregando.value = false;
    }
  };

  watch(
    () => chaveDaEscolha({ contato: contato.value, canal: canal.value }),
    () => {
      destino.value = DESTINOS.CONTINUAR;
      carregar();
    },
    { immediate: true }
  );

  return {
    destino,
    existente,
    oculta,
    conversa,
    tipo,
    carregando,
    erro,
    esperando,
    carregar,
    assunto,
    ultimoEmail,
  };
}
