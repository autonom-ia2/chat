// Roteiro do vídeo de trajeto do artigo 07.09 — "Criar uma caixa de e-mail
// ou de site (chat ao vivo)". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chaves
// INBOX_MGMT.ADD.AUTH.CHANNEL.EMAIL, INBOX_MGMT.EMAIL_PROVIDERS,
// INBOX_MGMT.ADD.EMAIL_CHANNEL.* e INBOX_MGMT.ADD.AGENTS.*).
//
// Vídeo prioritário do lote (pedido do Rodrigo: quase ninguém sabe
// conectar e-mail). Cobre só a parte de E-MAIL do artigo (que também fala
// de site/chat ao vivo) — as duas não cabem com folga em 40s dentro da
// regra "se couber, mostre as duas; senão, priorize o e-mail".
//
// Trajeto real, sem pular nenhum passo do assistente: Configurações →
// Caixas de Entrada → Adicionar Caixa de Entrada → E-mail → Outros
// Provedores → nome do canal + e-mail de destino → Criar canal de e-mail →
// (o assistente exige pelo menos 1 agente) escolher uma atendente → Adicionar
// agentes → tela final, com o link para configurar SMTP/IMAP em destaque.
// Não é possível parar antes do passo de agentes: o formulário de agentes
// tem validação obrigatória (pelo menos 1 selecionado) e não há URL
// previsível para pular direto (o id da caixa só existe depois de criada).
//
// Sem serviço de fora: e-mail "outro provedor" só grava um Channel::Email
// local (sem OAuth, sem SMTP/IMAP de verdade) — por isso o clique em
// "Criar canal de e-mail" acontece de verdade, ao contrário de Microsoft/
// Google (que abririam OAuth real e não entram neste vídeo).
//
// Endereço de encaminhamento: MAILER_INBOUND_EMAIL_DOMAIN não está
// configurado neste ambiente de dev (sem .env, .env.example vem vazio) —
// `forwarding_enabled` fica false e a tela final não mostra endereço de
// encaminhamento nenhum (mensagem "FINISH_MESSAGE_NO_FORWARDING"). O vídeo
// termina no link real que o artigo pede para seguir: "configurar as
// credenciais de SMTP e IMAP".
//
// Marca proibida: o assistente inteiro (InboxChannels.vue) tem, na coluna
// da esquerda, o resumo dos 4 passos com o nome da instalação
// ("...integrar com o Autonom.ia.", via replaceInstallationName) — mesmo
// risco já documentado em 07.02/07.08. Todo alvo deste roteiro fica na
// coluna de conteúdo (col-span-6, a partir de x≈482 CSS); zoom travado em
// 1,8× para não alcançar essa borda em nenhuma cena.

export const id = '07.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_CAIXA = 'E-mail Atendimento';
const EMAIL_DESTINO = 'atendimento@desnorteada.test';
const NOME_ATENDENTE = 'Bia Vendas';

// Idempotente: apaga qualquer sobra de uma gravação anterior deste mesmo
// vídeo (mesmo e-mail, mesmo nome de caixa) antes de gravar de novo — sem
// isso o e-mail (único no banco) e o nome batem com o que já existe e a
// criação real, no meio da gravação, falharia. Só mexe no que este vídeo
// cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
canal = Channel::Email.find_by(email: ${JSON.stringify(EMAIL_DESTINO)})
if canal
  inbox = Inbox.find_by(channel: canal)
  if inbox
    InboxMember.where(inbox: inbox).destroy_all
    Conversation.where(inbox: inbox).find_each do |c|
      Message.where(conversation: c).delete_all
      c.destroy!
    end
    ContactInbox.where(inbox: inbox).delete_all
    inbox.destroy!
  end
  canal.destroy!
end
extra = conta.inboxes.find_by(name: ${JSON.stringify(NOME_CAIXA)})
extra&.destroy!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar uma caixa de e-mail',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/new`,
    // innerText reflete o CSS `capitalize` do título do cartão (h3), que
    // exibe "E-Mail" (M maiúsculo) mesmo com o texto de origem "E-mail" —
    // só o innerText muda, o textContent usado no clique (mais abaixo)
    // continua "E-mail".
    aguardarTexto: 'E-Mail',
    zoom: 1.8,
    duracaoMs: 2000,
  },
  {
    legenda: 'Clique em E-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'E-mail' },
    zoom: 1.8,
    aguardarTextoDepois: 'Outros Provedores',
  },
  {
    legenda: 'Escolha Outros Provedores',
    acao: 'mover e clicar',
    alvo: { texto: 'Outros Provedores' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o Nome do Canal',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Por favor, insira um nome de canal"]',
    },
    texto: [NOME_CAIXA],
    zoom: 1.8,
  },
  {
    legenda: 'Digite o e-mail de destino',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="E-mail"]' },
    texto: [EMAIL_DESTINO],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar canal de e-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar canal de e-mail' },
    zoom: 1.8,
    // O placeholder do campo de busca de agentes não entra no innerText —
    // espera um trecho real da descrição da tela de Agentes.
    aguardarTextoDepois: 'gerenciar sua caixa de entrada recém-criada',
  },
  {
    legenda: 'Digite o nome da atendente',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Escolha agentes para a caixa de entrada"]',
    },
    texto: ['Bia'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha quem vai atender',
    acao: 'mover e clicar',
    alvo: { texto: NOME_ATENDENTE },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar agentes',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar agentes' },
    zoom: 1.8,
    aguardarTextoDepois: 'configurar IMAP e SMTP',
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Clique aqui' },
    zoom: 1.8,
    duracaoMs: 2400,
  },
];
