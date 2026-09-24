// Roteiro do vídeo de trajeto do artigo 08.12 — "Buscar contato, conversa
// ou mensagem". Busca por "Ricardo" acha o contato, a conversa e a mensagem
// criados pelo vídeo 08.08 (mesma conta de teste) — dado real da conta, sem
// precisar inventar mais nada.
//
// Seletores conferidos no código-fonte:
// - abrir a busca: link "Pesquisar..." na barra lateral, rota 'search'
//   (Sidebar.vue, COMBOBOX.SEARCH_PLACEHOLDER).
// - campo de busca: SearchInput.vue, único `input[type="search"]` da tela.
// - abas: SEARCH.TABS (Todos os resultados/Contatos/Conversas/Mensagens).
//
// Trajeto: Pesquisar → digita "Ricardo" → Todos os resultados → Contatos →
// Conversas → Mensagens → abre o contato.

export const id = '08.12';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a criar: reaproveita o contato/conversa "Ricardo Nunes" que o 08.08
// já deixa na conta. Só garante que ele existe, para este vídeo não
// depender da ordem de gravação dos outros.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
contato = conta.contacts.find_or_create_by!(name: "Ricardo Nunes") do |c|
  c.email = "ricardo-nunes@cliente.test"
  c.phone_number = "+5511990000033"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
end
conversa.messages.where(message_type: :incoming).first ||
  conversa.messages.create!(content: "Posso mandar os documentos da proposta por aqui?", message_type: :incoming, account: conta, inbox: inbox, sender: contato)

usuaria = conta.users.find_by!(name: ${JSON.stringify(login.usuarioNome)})

# Resposta com o nome do contato no texto — sem ela a busca por "Ricardo"
# não acha nada na aba Mensagens (o conteúdo da mensagem de cliente não
# cita o próprio nome).
conversa.messages.where(message_type: :outgoing).first ||
  conversa.messages.create!(content: "Pode mandar sim, Ricardo! Fico no aguardo dos documentos.", message_type: :outgoing, account: conta, inbox: inbox, sender: usuaria)
config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Buscar contato, conversa ou mensagem',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique em Pesquisar',
    acao: 'mover e clicar',
    alvo: { texto: 'Pesquisar...' },
    zoom: 1.4,
  },
  {
    legenda: 'Digite pelo menos 2 caracteres',
    acao: 'digitar',
    alvo: { seletor: 'input[type="search"]' },
    texto: ['Ricardo'],
    zoom: 1.6,
  },
  {
    legenda: 'Veja o resultado em cada aba',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2000,
  },
  {
    // Texto puro ("Contatos"/"Conversas") também é nome de item do MENU
    // LATERAL, que continua visível ao lado da tela de busca — sem
    // escopo, o motor acerta o menu, não a aba, e a gravação sai da busca
    // sem erro nenhum. `.h-8.rounded-lg.bg-n-alpha-1` é a barra de abas em
    // si (TabBar.vue), única na tela.
    legenda: 'Clique em Contatos',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Contatos (1)',
      dentro: { seletor: '.h-8.rounded-lg.bg-n-alpha-1' },
    },
    zoom: 1.4,
  },
  {
    legenda: 'Clique em Conversas',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Conversas (1)',
      dentro: { seletor: '.h-8.rounded-lg.bg-n-alpha-1' },
    },
    zoom: 1.4,
  },
  {
    legenda: 'Clique em Mensagens',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Mensagens (1)',
      dentro: { seletor: '.h-8.rounded-lg.bg-n-alpha-1' },
    },
    zoom: 1.4,
  },
  {
    // Volta para Contatos: na aba Mensagens o item mostra quem ESCREVEU a
    // mensagem (aqui, "Lia Admin"), não o nome do contato — não dá pra
    // clicar em "Ricardo Nunes" a partir dali.
    legenda: 'Clique no resultado para abrir',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Contatos (1)',
      dentro: { seletor: '.h-8.rounded-lg.bg-n-alpha-1' },
    },
    zoom: 1.4,
  },
  {
    legenda: 'Clique no contato para abrir',
    acao: 'mover e clicar',
    alvo: { texto: 'Ricardo Nunes' },
    zoom: 1.5,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
