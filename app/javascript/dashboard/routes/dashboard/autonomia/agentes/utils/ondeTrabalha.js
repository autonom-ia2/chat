// #1366 (protótipo da Fase 2, rodada 2) — leituras da jornada "Onde trabalha" que não dependem de tela.

// Caixa da store pelo nome que o papel guarda (o servidor de verdade vai mandar o id).
export const caixaPeloNome = (caixas, nome) =>
  (caixas || []).find(caixa => caixa.name === nome) || null;

// O que identifica o canal para quem lê: o número do WhatsApp; nos outros, o nome já basta.
export const enderecoDaCaixa = caixa =>
  caixa?.channel_type === 'Channel::Whatsapp' ? caixa.phone_number || '' : '';

// Quem atende primeiro em cada caixa, tirando o próprio agente: { [nomeDaCaixa]: nomeDoAgente }.
export const portasOcupadas = (agentes, papelDe, proprioId) =>
  (agentes || []).reduce((portas, agente) => {
    if (agente.id === proprioId) return portas;
    (papelDe(agente)?.caixas || [])
      .filter(item => item.papel === 'primeiro')
      .forEach(item => {
        portas[item.caixa] = agente.name;
      });
    return portas;
  }, {});

// Agentes que conversam com clientes: os que podem ser ajudados.
export const agentesPrincipais = (agentes, papelDe, proprioId) =>
  (agentes || []).filter(
    agente => agente.id !== proprioId && papelDe(agente)?.tipo === 'clientes'
  );
