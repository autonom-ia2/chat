// Roteiro do vídeo de trajeto do artigo 08.13 — "Usar o Copiloto na
// conversa". O artigo cobre dois recursos de IA: o bloco Copiloto (painel de
// Contatos, resume/rascunha) e o painel Copiloto Autonom.ia (chat com um
// agente interno, botão de estrelinhas). Os dois chamam a IA de verdade ao
// clicar em Resumir/Sugerir resposta/Reescrever/Refinar ou ao enviar uma
// pergunta — nenhuma dessas ações é clicada aqui (regra do Rodrigo para este
// vídeo). O vídeo mostra onde cada bloco fica e, no painel Copiloto
// Autonom.ia, digita a pergunta até o campo preenchido, sem enviar.
//
// Por isso o vídeo fica PARCIAL: os passos 2-4 do bloco Copiloto (escolher
// tom, refinar, inserir) só aparecem depois de uma resposta da IA, que não
// existe aqui; e o passo 4 do painel Copiloto Autonom.ia (enviar e ver a
// resposta) também não é mostrado.
//
// Seletores conferidos no código-fonte:
// - bloco Copiloto: CrmCopilotPanel.vue, botões "Resumir"/"Sugerir
//   resposta" (crm.json CRM_KANBAN.COPILOT.SUMMARIZE/DRAFT).
// - botão de estrelinhas: SidepanelSwitch.vue, ícone `.i-lucide-sparkles`,
//   só aparece com crmKanbanEnabled && crmCopilotEnabled (CRM_COPILOT_ENABLED
//   no servidor).
// - painel aberto: AutonomiaCopilotContainer.vue, texto de abertura
//   (AUTONOMIA_COPILOT.KICK_OFF) e seletor de agente
//   (ToggleCopilotAssistant.vue, só aparece com mais de 1 agente — a conta
//   de teste já tem "Léo Copiloto" e "Vale Copiloto" ativos, agentes
//   compartilhados que este vídeo só lê, não cria nem apaga).
// - campo de pergunta: CopilotInput.vue, único `<textarea>` da tela nesse
//   estado (painel de Contatos fecha ao abrir o Copiloto Autonom.ia).
//
// Trajeto: conversa própria → painel Contatos → bloco Copiloto (mostra, não
// clica) → botão de estrelinhas → painel Copiloto Autonom.ia → troca de
// agente → digita a pergunta → para, sem enviar.

export const id = '08.13';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

// Conversa fictícia PRÓPRIA deste vídeo (contato "Marcia Ribeiro"), para não
// mexer nas conversas compartilhadas com os outros agentes. Fica sempre a
// mais recente da conta, então o card `.conversation` (primeiro da lista)
// sempre acerta ela.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
contato = conta.contacts.find_or_create_by!(name: "Marcia Ribeiro") do |c|
  c.email = "marcia-ribeiro@cliente.test"
  c.phone_number = "+5511990000066"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
end
conversa.update!(status: :open, assignee_id: nil, team_id: nil, snoozed_until: nil)
msg = conversa.messages.where(message_type: :incoming).first
if msg.nil?
  msg = conversa.messages.create!(content: "Minha apolice de auto vence semana que vem, quero renovar", message_type: :incoming, account: conta, inbox: inbox, sender: contato)
end
conversa.update_columns(last_activity_at: Time.current)

usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
config = (usuaria.ui_settings || {}).merge(
  "channel_api_signature_enabled" => false,
  "is_contact_sidebar_open" => true,
  "is_copilot_panel_open" => false,
  "is_autonomia_copilot_panel_open" => false,
  "preferred_autonomia_copilot_agent_id" => nil,
  "is_conv_actions_open" => true
)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Usar o Copiloto na conversa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    zoom: 1.5,
  },
  {
    legenda: 'Abra sua conversa',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'No painel Contatos, bloco Copiloto',
    acao: 'parar',
    alvo: { texto: 'Resumir' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Ou peça um rascunho de resposta',
    acao: 'parar',
    alvo: { texto: 'Sugerir resposta' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique no botão de estrelinhas',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-sparkles' },
    // Sem isso, o quadro de depois do clique pode pegar o painel no
    // instante entre abrir e a lista de agentes carregar — nesse instante o
    // título ainda é o genérico "Copiloto Autonom.ia" (marca de verdade),
    // porque activeAgent ainda é null. Espera o nome do agente resolvido.
    aguardarTextoDepois: 'Léo Copiloto',
    // O botão tem v-tooltip.bottom com o texto "Copiloto Autonom.ia" (marca
    // de verdade) — sem dwell antes do clique, o cursor não fica parado
    // tempo suficiente para o tooltip nascer no DOM antes da checagem de
    // marca do segmento "antes do clique".
    pausaAntesMs: 0,
    zoom: 1.8,
  },
  {
    legenda: 'Abre o painel Copiloto Autonom.ia',
    acao: 'parar',
    alvo: {
      texto:
        'Pergunte ao copiloto sobre esta conversa: resumo, próximos passos, rascunho de resposta.',
    },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Escolha o agente no seletor',
    acao: 'mover e clicar',
    // Não usa alvo por texto "Léo Copiloto": o mesmo texto aparece também
    // no título do painel (mais acima), e o motor acerta o mais específico
    // dos dois, não necessariamente o botão do seletor. `.i-woot-captain`
    // sozinho também não serve: é o mesmo ícone do item "Capitão" do menu
    // lateral (um `<a>`, não um `<button>`), que vem antes no DOM e ganha
    // de um querySelector simples. `button .i-woot-captain` escopa para
    // dentro de um `<button>` — só o seletor de agente usa esse ícone num
    // botão (o botão do Copiloto nativo, mesmo ícone, some quando o
    // Copiloto Autonom.ia está aberto).
    alvo: { seletor: 'button .i-woot-captain' },
    zoom: 1.6,
  },
  {
    legenda: 'Troque de agente, se houver mais de um',
    acao: 'mover e clicar',
    alvo: { texto: 'Vale Copiloto' },
    zoom: 1.5,
  },
  {
    legenda: 'Digite sua pergunta',
    acao: 'digitar',
    alvo: { seletor: 'textarea' },
    texto: ['Qual o resumo desta conversa até agora?'],
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2400,
  },
];
