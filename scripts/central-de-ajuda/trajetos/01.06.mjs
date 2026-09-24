// Roteiro do vídeo de trajeto do artigo 01.06 — "Buscar tudo: a busca e a
// paleta de comandos". O artigo cobre DOIS recursos: a busca (achar algo
// que já existe) e a paleta de comandos, Cmd+K/Ctrl+K (ir a algum lugar ou
// rodar uma ação rápida).
//
// A paleta de comandos NÃO entra neste vídeo — precisa do atalho de
// teclado Cmd+K/Ctrl+K, e o roteiro não tem ação de tecla (só clique,
// digitação em campo focado, arrastar, navegação de URL). O único jeito de
// abri-la por clique que o código tem é um item do menu do perfil que
// pula direto para o submenu de Aparência (SidebarProfileMenu.vue), o que
// não mostra o uso geral do artigo (digitar "Times", "Atribuir time"...).
// Ver "precisa de motor" na entrega final.
//
// A busca reaproveita o contato/conversa "Ricardo Nunes" que o 08.08/08.12
// já deixam na conta — dado real, sem inventar mais nada.
//
// Seletores conferidos no código-fonte (iguais aos do 08.12):
// - abrir a busca: link "Pesquisar..." na barra lateral.
// - campo: `input[type="search"]`.
// - abas: `.h-8.rounded-lg.bg-n-alpha-1` (única barra de abas da tela —
//   texto puro "Contatos"/"Conversas" colide com o menu lateral).
//
// Trajeto: Pesquisar → digita "Ricardo" → Todos os resultados → Contatos →
// abre o contato.

export const id = '01.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

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
config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Buscar tudo: a busca',
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
    legenda: 'Veja os resultados agrupados',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2000,
  },
  {
    legenda: 'Entre na aba do tipo que quer',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Contatos (1)',
      dentro: { seletor: '.h-8.rounded-lg.bg-n-alpha-1' },
    },
    zoom: 1.4,
  },
  {
    legenda: 'Clique no resultado para abrir',
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
