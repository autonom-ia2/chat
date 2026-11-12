import { todosOsPassos } from './receita';

// #2574 (F5.4) — o que a automação faz que pede confirmação antes de ligar:
// mandar mensagem aos clientes, avisar a equipe ou usar IA (paga na chave da
// conta). Sem nada disso, ela liga direto, como antes. Olha todos os passos,
// também os de dentro dos galhos.
// "Passar para a agente de IA" (ia_assumir): a agente fala com o cliente. Conta
// como mensagem aos clientes e tem frase própria; não entra na soma do custo,
// que é o dos passos que vão à IA uma vez por execução.
const AGENTE = 'ia_assumir';
const AOS_CLIENTES = ['mensagem', 'email', AGENTE];
const DA_IA = ['decidir', 'extrair', 'escrever', 'resumir', 'para_cada'];

const mandaAosClientes = passo =>
  AOS_CLIENTES.includes(passo.tipo) ||
  (passo.tipo === 'campanha' && passo.faz === 'disparar') ||
  (passo.tipo === 'escrever' && passo.destino === 'mensagem');

// No WhatsApp, fora da janela a mensagem só sai com modelo aprovado, que a
// Meta cobra (#2468); a campanha sempre sai com modelo.
const usaModeloDaMeta = passo =>
  (passo.tipo === 'mensagem' && Boolean(passo.modelo)) ||
  (passo.tipo === 'campanha' && passo.faz === 'disparar');

export const oQueLigarFaz = receita => {
  const passos = todosOsPassos(receita?.passos || []);
  const manda = passos.some(mandaAosClientes);
  const avisa = passos.some(passo => passo.tipo === 'avisar');
  const agente = passos.some(passo => passo.tipo === AGENTE);
  const ia = passos
    .filter(passo => DA_IA.includes(passo.tipo))
    .map(({ id, tipo }) => ({ id, tipo }));
  return {
    manda,
    avisa,
    agente,
    ia,
    modeloDaMeta: passos.some(usaModeloDaMeta),
    pede: manda || avisa || agente || ia.length > 0,
  };
};

// O custo de um passo de IA: a média real dele nos últimos 30 dias
// (CustosDaIa.por_passo) ou, se ainda não rodou, a estimativa do tipo dele
// (EstimativaDaIa: o modelo e uma ordem de tokens, sem chamar a IA).
const custoDoPasso = ({ id, tipo }, custos, estimativa) => {
  const real = custos?.[id];
  if (typeof real?.media === 'number') {
    return { valor: real.media, tokens: real.tokens, estimado: false };
  }
  const previsto = estimativa?.[tipo];
  if (typeof previsto?.custo_usd !== 'number') return null;
  return { valor: previsto.custo_usd, tokens: previsto.tokens, estimado: true };
};

// { valor, tokens, estimado } de uma execução, somando os passos de IA; null
// sem passo de IA ou sem como medir algum deles. `tokens` fica null quando um
// passo não os tem; `estimado` diz que entrou ao menos uma estimativa.
export const custoPorExecucao = (passosDaIa, { custos, estimativa } = {}) => {
  if (!passosDaIa.length) return null;
  const partes = passosDaIa.map(passo =>
    custoDoPasso(passo, custos, estimativa)
  );
  if (partes.some(parte => !parte)) return null;
  const comTokens = partes.every(parte => typeof parte.tokens === 'number');
  return {
    valor: partes.reduce((soma, parte) => soma + parte.valor, 0),
    tokens: comTokens
      ? partes.reduce((soma, parte) => soma + parte.tokens, 0)
      : null,
    estimado: partes.some(parte => parte.estimado),
  };
};
