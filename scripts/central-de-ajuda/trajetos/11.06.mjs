// Roteiro do vídeo de trajeto do artigo 11.06 — "Publicar um agente externo
// ou interno". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agents.json e no componente
// BuilderReview.vue (reaproveitado pela aba de publicação do painel,
// PanelPublish.vue).
//
// Este vídeo mostra o caminho de um agente INTERNO (copiloto): sem essa
// escolha, o passo "Escolha uma caixa de entrada" usa um <select> nativo do
// navegador, que o motor de gravação não consegue operar (sem ação de
// teclado/seleção de dropdown no roteiro — ver videos-instrucoes.md). O
// caminho interno cobre o mesmo "Como faz" do artigo, sem esse obstáculo.
//
// Trajeto: Meus agentes → agente em Rascunho (interno) → Revise seu agente →
// Ativar copiloto → confirmação na barra lateral direita de uma conversa.

export const id = '11.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Duda Admin',
};

export const baseUrl = 'http://localhost:3000';

// Garante um agente INTERNO em rascunho, pronto pra publicar — de forma
// idempotente: como este vídeo publica o agente (Ativar copiloto), cada
// gravação nova precisa encontrá-lo de volta em rascunho.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria

bia = Autonomia::Agents::Agent.find_or_initialize_by(account_id: conta.id, name: "Léo Copiloto")
bia.assign_attributes(
  agent_type: "custom",
  actuation: "internal",
  status: "draft",
  enabled: false,
  mode: "guided",
  human_card: "Ajuda a equipe a responder dúvidas sobre produtos durante o atendimento.",
  greeting: "Oi! Pergunte o que precisar sobre a conversa atual.",
  starter_questions: ["Resuma esta conversa", "Sugira uma resposta"],
  instruction: "Ajude o atendente com resumos e sugestões durante o atendimento ao cliente.",
  created_by_id: usuaria.id,
  config: { "with_knowledge" => false }
)
bia.save!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Publicar um agente interno',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Meus agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/agents`,
    aguardarTexto: 'Léo Copiloto',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Publicar no rascunho',
    acao: 'mover e clicar',
    alvo: { texto: 'Publicar' },
    zoom: 1.8,
  },
  {
    legenda: 'Leia o resumo em Revise seu agente',
    acao: 'parar',
    alvo: { texto: 'Revise seu agente' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Veja o bloco Agente interno',
    acao: 'parar',
    alvo: { texto: 'Agente interno (copiloto da equipe)' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    // A confirmação real é o toast "Copiloto ativado! Abra qualquer conversa
    // e encontre-o na barra lateral direita" — o ícone em si
    // (CRM_COPILOT_ENABLED) está desligado nesta instalação local, então a
    // cena seguinte não tenta mostrá-lo (ver relato ao Rodrigo).
    legenda: 'Clique em Ativar copiloto',
    acao: 'mover e clicar',
    alvo: { texto: 'Ativar copiloto' },
    zoom: 1.8,
    pausaDepoisMs: 1800,
  },
  {
    legenda: 'Copiloto ativado, confirmação na tela',
    acao: 'parar',
    alvo: {
      texto:
        'Copiloto ativado! Abra qualquer conversa e encontre-o na barra lateral direita.',
    },
    zoom: 1.5,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
