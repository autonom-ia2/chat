// Roteiro do vídeo de trajeto do artigo 13.02 — "Criar uma campanha de
// WhatsApp Oficial".
//
// A tela só lista caixas Channel::Whatsapp com pelo menos um modelo
// aprovado (getWhatsAppInboxes/getFilteredWhatsAppTemplates, ambos em
// app/javascript/dashboard/store/modules/inboxes.js) — a conta 9 não tinha
// nenhuma até o 07.05 (Téo, P1) criar "WhatsApp Renovação Norte". Este
// roteiro cria a SUA PRÓPRIA caixa (nome e telefone diferentes), do mesmo
// jeito que o 07.05: Channel::Whatsapp.skip_callback(:sync_templates) para
// nunca bater na Meta, provider "default" para não disparar setup de
// webhook.
//
// Serviço de fora (Meta/WhatsApp): o vídeo pára com o formulário inteiro
// preenchido, sem clicar em "Criar" — esse clique JÁ agenda a campanha de
// verdade (`campaigns/create` chama a API na hora, sem diálogo de
// confirmação). É o mesmo "nunca clique em Agendar" das regras do P2.

export const id = '13.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_CAIXA = 'WhatsApp Campanhas Oficiais';
const TELEFONE_CANAL = '5511900000411';
const NOME_MODELO = 'renovacao_seguro_auto';
const TITULO_FRIENDLY = 'Renovacao Seguro Auto (pt_BR)';
// Nome escolhido pra ordenar primeiro na lista de etiquetas (ordem
// alfabética) — com outra etiqueta client-side ANTES dela na lista, o
// TagMultiSelectComboBox às vezes marca as DUAS sozinho (o cursor
// atravessa a linha de cima a caminho da nossa, entre abrir a lista e
// clicar). Sendo a primeira da lista, não há linha pra atravessar.
const NOME_LABEL_PUBLICO = 'auto_seguro_publico_out';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA)}
telefone = ${JSON.stringify(TELEFONE_CANAL)}

# Idempotente: só mexe na caixa que ESTE roteiro cria (nome e telefone só
# usados aqui) — não toca em "WhatsApp Renovação Norte" (do 07.05).
existente = conta.inboxes.find_by(name: nome)
if existente
  Conversation.where(inbox_id: existente.id).destroy_all
  ContactInbox.where(inbox_id: existente.id).delete_all
  existente.destroy!
end
Channel::Whatsapp.where(phone_number: telefone).delete_all

Channel::Whatsapp.skip_callback(:create, :after, :sync_templates, raise: false)
canal = Channel::Whatsapp.new(
  account: conta,
  phone_number: telefone,
  provider: "default",
  provider_config: { "api_key" => "chave-fake-video" },
  message_templates: [
    {
      "id" => 1,
      "name" => ${JSON.stringify(NOME_MODELO)},
      "status" => "approved",
      "category" => "UTILITY",
      "language" => "pt_BR",
      "components" => [
        { "type" => "BODY", "text" => "Olá {{1}}, sua apólice de seguro auto está perto de vencer. Fale com a gente para renovar sem perder desconto." }
      ]
    }
  ],
  message_templates_last_updated: Time.now.utc,
  phone_number_health: {}
)
canal.save!(validate: false)
Inbox.create!(account: conta, name: nome, channel: canal)

conta.labels.find_or_create_by!(title: ${JSON.stringify(NOME_LABEL_PUBLICO)}) do |l|
  l.show_on_sidebar = false
end

puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar uma campanha de WhatsApp Oficial',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/campaigns/whatsapp`,
    aguardarTexto: 'Criar campanha',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique em Criar campanha',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar campanha' },
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o Título',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Por favor, digite o título da campanha"]',
    },
    texto: ['Renovacao de seguro auto - outubro'],
    zoom: 1.8,
  },
  {
    legenda: 'Selecione a caixa de entrada',
    acao: 'mover e clicar',
    alvo: { seletor: '#inbox' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha a caixa de WhatsApp',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CAIXA },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha o Modelo do WhatsApp',
    acao: 'mover e clicar',
    alvo: { seletor: '#template' },
    zoom: 1.8,
  },
  {
    legenda: 'Só aparecem modelos aprovados',
    acao: 'mover e clicar',
    alvo: { texto: TITULO_FRIENDLY },
    zoom: 1.5,
  },
  {
    legenda: 'Preencha a variável do modelo',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Insira o valor para 1"]' },
    texto: ['Beatriz'],
    zoom: 1.8,
  },
  {
    legenda: 'Marque o horário agendado',
    acao: 'definirValor',
    alvo: { seletor: 'input[type="datetime-local"]' },
    valor: '2026-12-01T09:00',
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o Público pela etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Selecionar etiquetas dos clientes' },
    zoom: 1.8,
  },
  {
    legenda: 'Marque a etiqueta dos contatos',
    acao: 'mover e clicar',
    alvo: { texto: NOME_LABEL_PUBLICO },
    zoom: 1.6,
    pausaAntesMs: 1800,
  },
  {
    // Fecho: mostra o Público certo, sem clicar em Criar — esse clique
    // agendaria a campanha de verdade.
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: NOME_LABEL_PUBLICO },
    zoom: 1.6,
    duracaoMs: 2200,
  },
];
