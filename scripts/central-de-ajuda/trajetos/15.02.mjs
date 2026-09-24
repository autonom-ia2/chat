// Roteiro do vídeo de trajeto do artigo 15.02 — "Criar o agente que cota
// com o cliente no WhatsApp". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/insurance.json (INSURANCE.AGENT).
// A gravação precisa de usuária com locale pt_BR (em en os rótulos mudam).
//
// Trajeto: Cotação → aba Agente → Configurar e criar → nome do agente,
// nome da corretora, horário, comportamento → Criar agente. Criação
// interna (Insurance::QuoteAgent::Builder monta o agente e os
// especialistas no banco); não conversa com o cliente nem chama serviço de
// fora — só a página inicial de Conexões (aba Conexões, não usada aqui)
// fala com o AGGER.
//
// Marca no próprio texto da tela: desde a #649 a nota e a descrição usam o
// nome da instalação ({installationName}, via useBranding), que fica sempre
// visível nesta aba (não dá para recortar o zoom para fora). O motor desfoca esse
// texto automaticamente (desfocarMarcasVisiveis, ligado por padrão) — não
// precisa de nada extra aqui.

export const id = '15.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_AGENTE = 'Sofia';
const NOME_CORRETORA = 'Corretora Desnorteada';
const HORARIO = 'de segunda a sexta, das 9h às 18h';

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
existente = Autonomia::Agents::Agent.where(account_id: account.id, agent_type: 'insurance_quote').first
if existente
  Autonomia::Agents::Specialist.where(agent_id: existente.id).destroy_all
  existente.destroy
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar o agente que cota no WhatsApp',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Cotação, aba Agente',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/autonomia/insurance/agent`,
    aguardarTexto: 'Configurar e criar',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Configurar e criar',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurar e criar' },
    aguardarTextoDepois: 'Nome do agente',
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o nome do agente',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Mia"]' },
    texto: [NOME_AGENTE],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o nome da corretora',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Corretora Exemplo"]' },
    texto: [NOME_CORRETORA],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o horário de atendimento',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="de segunda a sexta, das 09h às 18h"]',
    },
    texto: [HORARIO],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o comportamento Consultivo',
    acao: 'mover e clicar',
    alvo: { texto: 'Consultivo' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Criar agente',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar agente' },
    aguardarTextoDepois: 'já existe',
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
