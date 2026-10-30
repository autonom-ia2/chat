import { computed, onScopeDispose, ref, watch } from 'vue';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_TYPE } from 'shared/constants/messages';
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
// #1988 — o `can_reply` muda com a conversa viva (o cliente escreve e a janela de
// 24 h abre). Sem trocar de contato, canal ou conversa, a gaveta pergunta de novo,
// sem mexer na escolha nem no texto: quando os canais chegam de novo (a gaveta
// reaberta) e quando chega mensagem do cliente nessa conversa (websocket).
export function useContinuarConversa({ contato, canal }) {
  const destino = ref(DESTINOS.CONTINUAR);
  const podeResponder = ref(false);
  // #1809 — conversa de e-mail: o assunto dela (a resposta sai com "Re: ...") e o
  // último e-mail, que vai como histórico no fim, como na resposta.
  const assunto = ref('');
  const ultimoEmail = ref(null);
  // #2067: com quem a conversa está (meta do servidor: assignee e assignee_type), para o
  // ícone "ficar com a conversa ao enviar" ao lado do Enviar.
  const meta = ref(null);
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
  // #1988: novidade chegou enquanto a pergunta completa estava no ar.
  let pendente = false;

  // Pergunta de novo só o que a conversa aceita, sem "carregando": a mensagem fica
  // à vista e o que já foi escrito continua. Se esta falhar, vale a última resposta do
  // servidor (o erro com "Tentar de novo" é só da pergunta completa, que esconde a mensagem).
  const atualizar = async () => {
    const alvo = existente.value?.visible ? existente.value : null;
    if (!alvo) return;
    // A pergunta completa no ar pode ter saído antes da novidade: pergunta de novo depois.
    if (carregando.value) {
      pendente = true;
      return;
    }
    ultimoPedido += 1;
    const pedido = ultimoPedido;
    try {
      const { data } = await ConversationAPI.show(alvo.displayId);
      if (pedido !== ultimoPedido) return;
      podeResponder.value = data?.can_reply === true;
      meta.value = data?.meta || null;
    } catch (error) {
      // A resposta anterior continua valendo (ver acima).
    }
  };

  const carregar = async () => {
    ultimoPedido += 1;
    const pedido = ultimoPedido;
    const alvo = existente.value?.visible ? existente.value : null;
    podeResponder.value = false;
    assunto.value = '';
    ultimoEmail.value = null;
    meta.value = null;
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
      meta.value = data?.meta || null;
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
    if (pedido === ultimoPedido && !erro.value && pendente) {
      pendente = false;
      atualizar();
    }
  };

  // Trocar de contato, de canal ou de conversa encontrada zera a escolha e pergunta
  // tudo. Os mesmos canais lidos de novo (a gaveta reaberta, #1988) só perguntam
  // outra vez o que a conversa aceita: a janela pode ter aberto ou fechado.
  const chave = computed(() =>
    chaveDaEscolha({ contato: contato.value, canal: canal.value })
  );
  watch(
    [chave, existente],
    ([chaveAgora], [chaveAntes]) => {
      if (chaveAgora !== chaveAntes) {
        destino.value = DESTINOS.CONTINUAR;
        carregar();
        return;
      }
      atualizar();
    },
    { immediate: true }
  );

  // Mensagem do cliente nesta conversa, ao vivo: a janela de 24 h pode ter aberto.
  const aoChegarMensagem = mensagem => {
    const alvo = existente.value;
    if (!alvo || podeResponder.value) return;
    if (mensagem?.message_type !== MESSAGE_TYPE.INCOMING) return;
    if (String(mensagem.conversation_id) !== String(alvo.displayId)) return;
    atualizar();
  };
  emitter.on(BUS_EVENTS.MENSAGEM_AO_VIVO, aoChegarMensagem);
  onScopeDispose(() =>
    emitter.off(BUS_EVENTS.MENSAGEM_AO_VIVO, aoChegarMensagem)
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
    atualizar,
    assunto,
    ultimoEmail,
    meta,
  };
}
