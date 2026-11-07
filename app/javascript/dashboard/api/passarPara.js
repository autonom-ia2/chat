// PROTÓTIPO #1593 — ADAPTADOR FALSO. Nada aqui fala com o servidor sobre agentes de IA: o back ainda não existe.
// Quando existir, cada função vira uma chamada (a assinatura fica a mesma) e o resto da tela não muda:
//   agentesDaAtribuicao  → vem junto do ai_settings do funil (Crm::Ai::SettingsPresenter, campo ai_agents)
//   paraServidor/doServidor → somem: o servidor passa a aceitar handoff.pool_type 'ai_agent' + pool_id
//   quemPodeReceber      → GET  /api/v1/accounts/:id/conversations/:id/passar_para
//   passar               → POST /api/v1/accounts/:id/conversations/:id/passar_para
//                          (pessoa: a atribuição de hoje; agente: Autonomia::Agents::PassarParaIa.call)
//   comQuemEsta          → vem na própria conversa (ai_assignee + a origem da última passagem)
//   clientePedeVolta     → não existe na tela: é o agente de IA que devolve à origem quando o cliente pede
//
// Toda passagem guarda a ORIGEM: quem passou. Com um agente de IA na conversa, a origem aparece no selo, no topo do
// "Passar para…" ("Devolver para …") e é para ela que a conversa volta quando o cliente pede.
//
// Estados da demo pelo endereço (?demo=...): sem-fase2 | parado | sem-vinculo | simular (mostra o botão que imita o
// cliente pedindo para voltar). O que a pessoa escolhe fica só nesta aba (sessionStorage).
import ConversationApi from './inbox/conversation';

const GUARDADO = 'demo1593';

// Os agentes que atendem cliente nas caixas da conta de demonstração. Clara é a porta (o robô que atende primeiro);
// Lia e Maria são agentes da equipe da caixa (áreas); Marta está parada. "E-mail Contato" é caixa só de pessoas: não
// tem robô, e a Lia só responde lá quando recebe a passagem. Interno, Copiloto e ajudante nunca aparecem aqui.
const AGENTES = [
  {
    id: 1,
    name: 'Lia',
    parado: false,
    caixas: ['WhatsApp Vendas', 'E-mail Contato'],
  },
  {
    id: 2,
    name: 'Maria',
    parado: false,
    caixas: ['WhatsApp Vendas', 'WhatsApp Atendimento'],
  },
  {
    id: 3,
    name: 'Clara',
    parado: false,
    porta: true,
    caixas: ['WhatsApp Vendas', 'WhatsApp Atendimento'],
  },
  { id: 4, name: 'Marta', parado: true, caixas: ['WhatsApp Vendas'] },
];

export const PREFIXO_IA = 'ia:';
export const ehAgente = valor => String(valor || '').startsWith(PREFIXO_IA);
export const idDoAgente = valor =>
  Number(String(valor).slice(PREFIXO_IA.length));

const demo = () => new URLSearchParams(window.location.search).get('demo');
const temFase2 = () => demo() !== 'sem-fase2';
export const simulando = () => demo() === 'simular';
const espera = (ms = 250) =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const ler = () => {
  try {
    return JSON.parse(sessionStorage.getItem(GUARDADO)) || {};
  } catch {
    return {};
  }
};
const gravar = dados => {
  try {
    sessionStorage.setItem(GUARDADO, JSON.stringify(dados));
  } catch {
    // aba anônima sem armazenamento: a escolha vale só até recarregar
  }
};

// ---- Atribuição do funil ----------------------------------------------------------------------------------------

export const agentesDaAtribuicao = async () => {
  await espera();
  if (!temFase2()) return { fase2: false, agentes: [] };
  return {
    fase2: true,
    agentes: AGENTES.map(agente => ({
      id: agente.id,
      name: agente.name,
      parado: agente.parado,
      caixas: demo() === 'sem-vinculo' && agente.id === 1 ? [] : agente.caixas,
    })),
  };
};

// Hoje o servidor só conhece pessoa em pool_id. Na demo, quando a regra aponta para um agente ("ia:1"), o servidor
// recebe a regra antiga ("alguém da equipe") e a escolha fica guardada aqui.
export const paraServidor = (chave, regra) => {
  const dados = ler();
  const regras = { ...(dados.regras || {}) };
  if (ehAgente(regra.pool_id)) {
    regras[chave] = regra.pool_id;
    gravar({ ...dados, regras });
    return { ...regra, pool_type: 'inbox', pool_id: null };
  }
  delete regras[chave];
  gravar({ ...dados, regras });
  return regra;
};

export const doServidor = (chave, regra) => {
  if (!temFase2()) return regra;
  if (demo() === 'parado' && chave === 'funil') {
    return { ...regra, pool_type: 'user', pool_id: `${PREFIXO_IA}4` };
  }
  const guardado = (ler().regras || {})[chave];
  return guardado ? { ...regra, pool_type: 'user', pool_id: guardado } : regra;
};

// ---- Passar a conversa ------------------------------------------------------------------------------------------

// Cada passagem: { para: "ia:1" | id da pessoa, por: { id, name } | null, em }.
const historico = conversaId => (ler().conversas || {})[conversaId] || [];

const anotar = (conversaId, passagem) => {
  const dados = ler();
  const conversas = { ...(dados.conversas || {}) };
  conversas[conversaId] = [
    ...historico(conversaId),
    { ...passagem, em: Date.now() },
  ];
  gravar({ ...dados, conversas });
};

// Quem está com a conversa segundo a demo: o agente de IA e a origem (quem passou para ele).
export const comQuemEsta = conversaId => {
  const ultima = historico(conversaId).at(-1);
  if (!ultima || !ehAgente(ultima.para)) return null;
  const agente = AGENTES.find(item => item.id === idDoAgente(ultima.para));
  return agente ? { agente, origem: ultima.por } : null;
};

export const quemPodeReceber = async ({ conversaId, caixa }) => {
  await espera();
  if (!temFase2()) return { fase2: false, agentes: [], semRobo: false };
  const daCaixa = AGENTES.filter(agente => agente.caixas.includes(caixa));
  return {
    fase2: true,
    semRobo: !daCaixa.some(agente => agente.porta),
    origem: comQuemEsta(conversaId)?.origem || null,
    agentes: daCaixa
      .filter(agente => !agente.parado)
      .map(agente => ({ id: agente.id, name: agente.name })),
  };
};

// Recusas do servidor, em linguagem simples na tela: parado, sem_vinculo, sem_fase2, resolvida.
export class Recusa extends Error {
  constructor(motivo, campos = {}) {
    super(motivo);
    this.motivo = motivo;
    this.campos = campos;
  }
}

// Devolve a pessoa atribuída depois da passagem (null quando um agente de IA assume), para a tela atualizar.
// `por` é a pessoa que está passando: vira a origem.
export const passar = async ({ conversaId, valor, por }) => {
  if (!ehAgente(valor)) {
    const { data } = await ConversationApi.assignAgent({
      conversationId: conversaId,
      agentId: valor,
    });
    anotar(conversaId, { para: valor, por });
    return { assignee: data };
  }
  await espera(500);
  const agente = AGENTES.find(item => item.id === idDoAgente(valor));
  if (!temFase2()) throw new Recusa('sem_fase2');
  const lia = agente.id === 1;
  if (lia && demo() === 'parado') {
    throw new Recusa('parado', { nome: agente.name });
  }
  if (lia && demo() === 'sem-vinculo') {
    throw new Recusa('sem_vinculo', { nome: agente.name });
  }
  // No back de verdade, o PassarParaIa troca o ai_assignee, guarda a origem e solta a pessoa; aqui só a pessoa sai.
  await ConversationApi.assignAgent({
    conversationId: conversaId,
    agentId: null,
  });
  anotar(conversaId, { para: valor, por });
  return { assignee: null };
};

// Imita o agente de IA devolvendo à origem quando o cliente pede ("pode voltar a falar com a Ana?"). No back, o
// modelo decide e chama a mesma passagem com por: :ia; aqui é o botão "Simular" da demo.
export const clientePedeVolta = async conversaId => {
  const atual = comQuemEsta(conversaId);
  if (!atual?.origem) return null;
  await espera(400);
  const { data } = await ConversationApi.assignAgent({
    conversationId: conversaId,
    agentId: atual.origem.id,
  });
  anotar(conversaId, {
    para: atual.origem.id,
    por: { id: `ia:${atual.agente.id}`, name: atual.agente.name },
  });
  return { assignee: data, origem: atual.origem, agente: atual.agente };
};
