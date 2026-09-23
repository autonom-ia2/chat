// Roteiro do vídeo de trajeto do artigo 07.05 — "A janela de 24 horas e o
// envio de modelos aprovados". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{conversation,whatsappTemplates}.json.
//
// Trajeto: abra a caixa de WhatsApp Oficial pela barra lateral → veja as
// conversas não atribuídas → abra a conversa travada → ícone de modelos →
// busque o modelo → escolha-o → preencha a variável.
//
// Dado de teste: como a conta 9 não tem nenhuma caixa de WhatsApp Oficial de
// verdade, o preparo cria uma (Channel::Whatsapp) só pra este vídeo, com um
// modelo aprovado fake e uma conversa cuja última mensagem do cliente tem
// 30h (fora da janela de 24h). A criação evita qualquer chamada de fora:
// pula o callback `sync_templates` (que bateria de verdade em
// waba.360dialog.io) e usa provider "default" (não "whatsapp_cloud", que
// dispararia setup de webhook).
//
// Serviço de fora (envio de WhatsApp): o vídeo pára com a variável do
// modelo preenchida, sem clicar em "Enviar Mensagem" — isso enviaria uma
// mensagem de verdade pela API do WhatsApp.
//
// IDs não são hardcoded (a caixa e a conversa nascem de novo a cada
// preparo, com ID diferente) — por isso a navegação usa cliques por texto
// (nome da caixa na barra lateral, nome do contato na lista) em vez de URL
// direta com o ID.

export const id = '07.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_CAIXA = 'WhatsApp Renovação Norte';
const TELEFONE_CANAL = '5511900000299';
const NOME_CONTATO = 'Paulo Ferreira';
const TELEFONE_CONTATO = '+5511999990299';
const NOME_MODELO = 'aviso_renovacao';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA)}
telefone = ${JSON.stringify(TELEFONE_CANAL)}
telefone_contato = ${JSON.stringify(TELEFONE_CONTATO)}

existente = conta.inboxes.find_by(name: nome)
if existente
  Conversation.where(inbox_id: existente.id).find_each do |c|
    Message.where(conversation_id: c.id).delete_all
    c.destroy!
  end
  ContactInbox.where(inbox_id: existente.id).delete_all
  existente.destroy!
end
Channel::Whatsapp.where(phone_number: telefone).delete_all
Contact.where(account_id: conta.id, phone_number: telefone_contato).destroy_all

Channel::Whatsapp.skip_callback(:create, :after, :sync_templates, raise: false)
canal = Channel::Whatsapp.new(
  account: conta,
  phone_number: telefone,
  provider: "default",
  provider_config: { "api_key" => "chave-fake-video" },
  message_templates: [
    {
      "name" => ${JSON.stringify(NOME_MODELO)},
      "status" => "approved",
      "category" => "UTILITY",
      "language" => "pt_BR",
      "components" => [
        { "type" => "BODY", "text" => "Olá {{1}}, sua proposta de renovação está pronta. Responda quando puder falar." }
      ]
    }
  ],
  message_templates_last_updated: Time.now.utc,
  phone_number_health: {}
)
canal.save!(validate: false)

inbox = Inbox.create!(account: conta, name: nome, channel: canal)
contato = Contact.create!(account: conta, name: ${JSON.stringify(NOME_CONTATO)}, phone_number: telefone_contato)
cid = ContactInbox.create!(contact: contato, inbox: inbox, source_id: telefone_contato.delete("+")).id
conversa = Conversation.create!(account: conta, inbox: inbox, contact: contato, contact_inbox_id: cid)
Message.create!(
  account: conta, conversation: conversa, inbox: inbox,
  message_type: :incoming, content: "Bom dia, ainda não recebi a proposta de renovação",
  sender: contato, created_at: 30.hours.ago
)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    // Abertura fundida com a navegação — mesma razão das outras: a página
    // pousada após o login não é confiável (viramos onboarding às vezes).
    // Página segura já usada em outros vídeos (sem marca, carrega rápido);
    // a barra lateral com as caixas já vem junto, pronta pro próximo clique.
    // "dashboard" é a home de Conversas de verdade (rota 'home' em
    // conversation.routes.js) — com ela, a seção "Canais" da barra lateral
    // já vem expandida, com o nome da caixa pronto pra clicar. Esperar
    // pelo NOME da caixa (não só "Canais") garante que a lista de canais
    // já carregou por completo — a busca de "mover e clicar" só tenta por
    // 4s, e essa lista às vezes demora mais que isso pra chegar da API;
    // "ir para" com aguardarTexto tem uma folga bem maior (até 12s).
    legenda: 'A janela de 24 horas travou a resposta',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/dashboard`,
    aguardarTexto: NOME_CAIXA,
    zoom: 1,
    duracaoMs: 1600,
  },
  {
    // Por texto não dá: o nome da caixa, na barra lateral, divide o mesmo
    // <div> com o identificador (telefone) num template v-if separado —
    // nenhum elemento tem como textContent exatamente "WhatsApp Renovação
    // Norte" sozinho (ChannelLeaf.vue). O atributo title (rowTitle) tem o
    // nome inteiro; casar por ele com [title*=...] resolve.
    legenda: 'Abra a caixa travada',
    acao: 'mover e clicar',
    alvo: {
      seletor: `a:has([data-test-id="channel-leaf-label"][title*="${NOME_CAIXA}"])`,
    },
    zoom: 2,
  },
  {
    // Mesmo problema de texto: a aba "Não atribuídas" divide o <a> com o
    // número da contagem (badge), sem separador — textContent vira "Não
    // atribuídas 3", não "Não atribuídas" sozinho. É a 2ª aba da lista
    // (Minhas, Não atribuídas, Todos), por posição.
    legenda: 'Veja as conversas não atribuídas',
    acao: 'mover e clicar',
    alvo: { seletor: 'ul.min-w-\\[6\\.25rem\\] li:nth-child(2) a' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra a conversa',
    acao: 'mover e clicar',
    alvo: { texto: NOME_CONTATO },
    zoom: 1.6,
  },
  {
    // O texto do artigo ("Você só pode responder...") é o PLACEHOLDER do
    // editor de resposta — placeholder não entra no textContent, por isso
    // o alvo é o contêiner da caixa de resposta, não o texto exato.
    legenda: 'Só dá pra responder com um modelo',
    acao: 'parar',
    alvo: { seletor: '.reply-box' },
    zoom: 1.3,
    duracaoMs: 1500,
  },
  {
    legenda: 'Clique no ícone de modelos',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-ph-whatsapp-logo' },
    zoom: 2.2,
  },
  {
    legenda: 'Busque o modelo pelo nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar modelos"]' },
    texto: ['aviso'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o modelo',
    acao: 'mover e clicar',
    alvo: { texto: NOME_MODELO },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o campo variável',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Insira o valor para 1"]' },
    texto: ['Paulo'],
    zoom: 1.8,
  },
  {
    // Fecho: mostra "Enviar Mensagem" em destaque, sem clicar (enviaria
    // mensagem de WhatsApp de verdade).
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Enviar Mensagem' },
    zoom: 2,
    duracaoMs: 2000,
  },
];
