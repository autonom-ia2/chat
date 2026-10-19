// Tema 14 (#1434) — leituras do ajudante ("Ajuda outros agentes"), sem tela. O ajudante é um agente
// interno que NASCEU como ajudante (`ajudante` do servidor, a marca de origem) e que outros agentes da
// conta consultam; nunca fala com o cliente e não tem canal. Quem ele ajuda vem em `ajuda` ([{ id, name }]).

const TIPO_COTACAO = 'insurance_quote';

export const BLOQUEIO_DE_PRINCIPAL = { COTACAO: 'cotacao' };

// Nasceu como ajudante, ou já ajuda alguém (payload sem a marca, ex.: cache antigo).
export const ehAjudante = agente =>
  agente?.ajudante === true || (agente?.ajuda || []).length > 0;

export const quemAjuda = agente => agente?.ajuda || [];

export const nomesQueAjuda = agente =>
  quemAjuda(agente)
    .map(principal => principal.name)
    .join(', ');

// Fala com o cliente: o Copiloto e os ajudantes (internos) não. Usado para escolher o principal (os rascunhos
// ficam fora; a Cotação aparece bloqueada com o motivo, e o servidor também a recusa) e na página do agente.
export const falaComCliente = agente =>
  agente.actuation !== 'internal' && !ehAjudante(agente);

const terminado = agente => Boolean(agente.status) && agente.status !== 'draft';

export const principaisPossiveis = (agentes, ajudanteId = null) =>
  (agentes || [])
    .filter(
      agente =>
        agente.id !== ajudanteId && falaComCliente(agente) && terminado(agente)
    )
    .map(agente => ({
      agente,
      bloqueio:
        agente.agent_type === TIPO_COTACAO
          ? BLOQUEIO_DE_PRINCIPAL.COTACAO
          : null,
    }));
