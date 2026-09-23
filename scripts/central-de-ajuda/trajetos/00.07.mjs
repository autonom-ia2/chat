// Roteiro do vídeo de trajeto do artigo 00.07 — "Passo 6 — Convidar quem
// vai atender". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/agentMgmt.json.
//
// Trajeto: Configurações → Agentes → Adicionar Agente → nome, e-mail →
// Adicionar agente. Convite interno (usuário + e-mail de convite), não
// chama serviço externo — em dev sem SMTP o próprio formulário mostra um
// link de convite manual em vez de falhar, então dá para completar.

export const id = '00.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

const EMAIL_AGENTE = 'camila.souza@desnorteada.test';
const NOME_AGENTE = 'Camila Souza';

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
email = ${JSON.stringify(EMAIL_AGENTE)}
existente = User.find_by(email: email)
if existente
  AccountUser.where(account_id: account.id, user_id: existente.id).destroy_all
  existente.destroy if existente.account_users.reload.empty?
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Convidar quem vai atender',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Agentes',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/agents/list`,
    aguardarTexto: 'Adicionar Agente',
    zoom: 1.2,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Adicionar Agente',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar Agente' },
    aguardarTextoDepois: 'Nome do Agente',
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Por favor, insira o nome do agente"]' },
    texto: [NOME_AGENTE],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o e-mail',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Por favor, insira um endereço de e-mail do agente"]',
    },
    texto: [EMAIL_AGENTE],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Adicionar agente',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar agente' },
    aguardarTextoDepois: NOME_AGENTE,
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
