// Reações do WhatsApp (#1702). Como no app, a reação não é balão: é um selo com o
// emoji encostado embaixo da mensagem reagida, com a contagem quando há mais de uma.
// O servidor grava em content_attributes.reactions da mensagem reagida, uma por autor
// (Whatsapp::ReactionRecorder). Aqui só se lê o que veio.

// Emojis diferentes que o selo mostra; o resto entra só na contagem (como no app).
export const EMOJIS_NO_SELO = 3;

export const reacoesDaMensagem = contentAttributes => {
  const lista = contentAttributes?.reactions;
  if (!Array.isArray(lista)) return [];
  return lista.filter(reacao => reacao && reacao.emoji);
};

// [{ emoji, total }] na ordem em que cada emoji apareceu primeiro.
export const agruparReacoes = reacoes =>
  reacoes.reduce((grupos, { emoji }) => {
    const grupo = grupos.find(item => item.emoji === emoji);
    return grupo
      ? grupos.map(item =>
          item === grupo ? { ...item, total: item.total + 1 } : item
        )
      : [...grupos, { emoji, total: 1 }];
  }, []);

// Com o agente da Autonomia na caixa, a reação também vira uma mensagem recebida
// "[O cliente reagiu com …]" para o agente ler. Com a pele, o selo já mostra a
// reação: essa mensagem fica fora da lista (continua existindo para o agente).
export const ehReacaoDoAgente = mensagem =>
  Boolean(mensagem?.contentAttributes?.autonomiaReaction);

const tipoDoAutor = reacao => reacao.senderType ?? reacao.sender_type;

// Uma frase por reação, para o leitor de tela e a dica ao passar o mouse.
// `nomeDoCliente` é o nome do contato da conversa (quem reage no 1:1).
export const descreverReacoes = (reacoes, { t, nomeDoCliente }) =>
  reacoes
    .map(reacao => {
      const nome =
        tipoDoAutor(reacao) === 'Contact'
          ? nomeDoCliente || t('CONVERSA_CANAL.REACOES.CLIENTE')
          : t('CONVERSA_CANAL.REACOES.EQUIPE');
      return t('CONVERSA_CANAL.REACOES.ROTULO', { nome, emoji: reacao.emoji });
    })
    .join('; ');
