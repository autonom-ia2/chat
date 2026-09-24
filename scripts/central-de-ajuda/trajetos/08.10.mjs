// Roteiro do vídeo de trajeto do artigo 08.10 — "Prioridade, etiquetas,
// participantes e macro na conversa". Os quatro ajustes vivem em acordeões
// fechados por padrão dentro do painel Contatos — abertos aqui via
// ui_settings (`is_conv_actions_open`, `is_macro_open`,
// `is_conv_participants_open`), não por clique no roteiro (evita depender
// do estado anterior do acordeão, que persiste por usuária entre sessões:
// clicar sem saber se já estava aberto pode FECHAR em vez de abrir).
//
// Seletores conferidos no código-fonte:
// - Prioridade: MultiselectDropdown.vue (shared/components/ui), botão
//   mostra o valor atual — "Nenhuma" é único entre os três dropdowns da
//   seção (Agente/Time usam "Nenhum", masculino; só Prioridade usa
//   "Nenhuma").
// - Etiquetas da conversa: LabelBox.vue → AddLabel.vue, botão
//   "Adicionar etiquetas" (CONTACT_PANEL.LABELS.CONVERSATION.ADD_BUTTON).
// - Macro: MacroItem.vue, ícone `.i-lucide-play` (Executar) — só existe uma
//   macro na conta (a que este vídeo cria, própria, com ação inofensiva de
//   etiquetar).
// - Participantes: ConversationParticipant.vue, botão "Participar da
//   conversa" (WATCH_CONVERSATION).
//
// Trajeto: conversa própria → Ações da conversa (Prioridade → Alta,
// Etiquetas → sinistro) → Macros (pré-visualizar e executar a macro própria)
// → Participantes (Participar da conversa).

export const id = '08.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_MACRO = 'Marcar como sinistro';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
usuaria = conta.users.find_by!(name: ${JSON.stringify(login.usuarioNome)})

contato = conta.contacts.find_or_create_by!(name: "Fabio Martins") do |c|
  c.email = "fabio-martins@cliente.test"
  c.phone_number = "+5511990000055"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
end
conversa.update!(status: :open, priority: nil)
conversa.messages.where(message_type: :incoming).first ||
  conversa.messages.create!(content: "Bati o carro no estacionamento, preciso abrir sinistro", message_type: :incoming, account: conta, inbox: inbox, sender: contato)
conversa.update_columns(last_activity_at: Time.current)

# Idempotente: garante que a etiqueta "sinistro" NÃO esteja aplicada ainda
# (senão o clique em "sinistro" no dropdown REMOVE em vez de adicionar) e
# que ninguém esteja participando (senão "Participar da conversa" já
# apareceria trocado por "Você está participando").
conversa.update!(label_list: conversa.label_list - ["sinistro"])
conversa.conversation_participants.destroy_all

# Macro PRÓPRIA (pessoal, dela), com uma ação inofensiva — só etiqueta.
# Sem ela a conta não tinha nenhuma macro, e o bloco Macros do painel
# ficaria vazio (o vídeo não teria o que pré-visualizar/executar).
macro = conta.macros.find_or_create_by!(name: ${JSON.stringify(NOME_MACRO)}) do |m|
  m.visibility = :personal
  m.created_by = usuaria
  m.actions = [{ "action_name" => "add_label", "action_params" => ["sinistro"] }]
end
macro.update!(actions: [{ "action_name" => "add_label", "action_params" => ["sinistro"] }], created_by: usuaria, visibility: :personal)

config = (usuaria.ui_settings || {}).merge(
  "channel_api_signature_enabled" => false,
  "is_contact_sidebar_open" => true,
  "is_copilot_panel_open" => false,
  "is_autonomia_copilot_panel_open" => false,
  "is_conv_actions_open" => true,
  "is_macro_open" => true,
  "is_conv_participants_open" => true
)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Prioridade, etiquetas e macro na conversa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1600,
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
    legenda: 'Em Ações da conversa, abra Prioridade',
    acao: 'mover e clicar',
    alvo: { texto: 'Nenhuma' },
    zoom: 1.8,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Escolha Alta',
    acao: 'mover e clicar',
    alvo: { texto: 'Alta' },
    zoom: 1.6,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Clique em Adicionar etiquetas',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar etiquetas' },
    zoom: 1.6,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Escolha a etiqueta sinistro',
    acao: 'mover e clicar',
    alvo: { texto: 'sinistro' },
    zoom: 1.6,
  },
  {
    legenda: 'Role até o bloco Macros',
    acao: 'parar',
    alvo: { texto: NOME_MACRO, blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 900,
  },
  {
    legenda: 'Clique no ícone de informação',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-info' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Executar',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-play' },
    zoom: 1.8,
  },
  {
    legenda: 'Role até Participantes',
    acao: 'parar',
    alvo: { texto: 'Participar da conversa', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 900,
  },
  {
    legenda: 'Clique em Participar da conversa',
    acao: 'mover e clicar',
    alvo: { texto: 'Participar da conversa' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1600,
  },
];
