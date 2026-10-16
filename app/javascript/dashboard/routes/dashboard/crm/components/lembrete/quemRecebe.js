// #1462 — quem recebe o aviso do lembrete. "dono" acompanha quem cuida do
// cliente (se o dono do card mudar, o aviso vai junto); "eu", "pessoas" e
// "time" ficam fixos. O criador sempre vê na agenda o que marcou.
export const quemRecebeVazio = (comCard = true) => ({
  tipo: comCard ? 'dono' : 'eu',
  pessoas: [],
  time: null,
});

// Os nomes de quem recebe, para a prévia e a lista ("Paula e Bruno").
export const nomesDeQuemRecebe = ({ quem, dono, eu, agentes, membros }) => {
  switch (quem.tipo) {
    case 'dono':
      return dono ? [dono] : [];
    case 'eu':
      return eu ? [eu] : [];
    case 'pessoas':
      return agentes
        .filter(agente => quem.pessoas.includes(agente.id))
        .map(agente => agente.name);
    case 'time':
      return membros[quem.time] || [];
    default:
      return [];
  }
};

export const quemRecebePronto = quem =>
  !(quem.tipo === 'pessoas' && !quem.pessoas.length) &&
  !(quem.tipo === 'time' && !quem.time);
