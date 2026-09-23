// Roteiro do vídeo de trajeto do artigo 11.05 — "Fechar a construção e
// revisar o agente". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json (AGENTS.REVIEW).
//
// IMPORTANTE (IA): a conversa real do Construtor dispara uma chamada de IA
// assim que a etapa abre (ver 11.02/11.03). Este vídeo evita isso: cria, pelo
// preparar, um agente em rascunho já como se a entrevista tivesse terminado
// (human_card/greeting/starter_questions prontos) e entra direto na tela de
// revisão pelo card do rascunho em Meus agentes — o mesmo atalho que o
// artigo 11.06 documenta ("leva direto para esta mesma tela").
//
// Trajeto: Meus agentes → agente em rascunho → Revise seu agente → editar
// Primeira mensagem → Salvar primeira mensagem → materiais aprovados.

export const id = '11.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria

rev = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: "Ana Suporte")
rev.assign_attributes(
  agent_type: "support",
  actuation: "external",
  status: "draft",
  enabled: false,
  mode: "guided",
  human_card: "Responde dúvidas sobre prazos de entrega e trocas de produtos.",
  # Vazio de propósito: a cena de digitação escreve a primeira mensagem do
  # zero (mesmo motivo do roteiro-modelo 02.04 — sem isso o texto novo
  # apenas se soma ao que já estava no campo).
  greeting: "",
  starter_questions: ["Qual o prazo de entrega?", "Como faço uma troca?"],
  instruction: "Responda dúvidas sobre prazos de entrega e trocas. Seja breve e cordial.",
  created_by_id: usuaria.id,
  config: { "with_knowledge" => true, "knowledge_confidence" => 0.82 }
)
rev.save!

fonte = Autonomia::Agents::Source.find_or_initialize_by(
  account_id: conta.id, autonomia_agent_id: rev.id, source_type: "link",
  reference: "https://www.desnorteada.test/prazos-e-trocas"
)
fonte.assign_attributes(
  kind: "knowledge",
  status: "ready",
  review_status: "accepted",
  review_label: "boa",
  external_link: "https://www.desnorteada.test/prazos-e-trocas",
  metadata: {}
)
fonte.save!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Revisar o agente antes de publicar',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Meus agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/agents`,
    aguardarTexto: 'Ana Suporte',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique no agente em rascunho',
    acao: 'mover e clicar',
    alvo: { texto: 'Ana Suporte' },
    zoom: 1.6,
  },
  {
    legenda: 'Tela muda para Revise seu agente',
    acao: 'parar',
    alvo: { texto: 'Revise seu agente' },
    zoom: 1.4,
    duracaoMs: 1600,
  },
  {
    legenda: 'Leia o resumo do agente',
    acao: 'parar',
    alvo: {
      texto: 'Responde dúvidas sobre prazos de entrega e trocas de produtos.',
    },
    zoom: 1.5,
    duracaoMs: 1600,
  },
  {
    legenda: 'Ajuste a Primeira mensagem',
    acao: 'digitar',
    alvo: { seletor: 'textarea' },
    texto: ['Oi! Sou a assistente virtual da loja. Como posso ajudar?'],
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Salvar primeira mensagem',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar primeira mensagem' },
    zoom: 1.8,
    pausaDepoisMs: 1200,
  },
  {
    legenda: 'Veja materiais aprovados e confiança',
    acao: 'parar',
    alvo: { texto: '1 materiais aprovados · confiança 82%' },
    zoom: 1.5,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
];
