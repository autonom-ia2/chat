// Roteiro do vídeo de trajeto do artigo 07.03 — "Colocar atendentes e ler as
// abas da caixa". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{inboxMgmt,agentMgmt}.json.
//
// Trajeto: Configurações → Caixas de Entrada → a caixa de teste → aba
// Agentes → digitar o nome → escolher a pessoa → Atualizar.
//
// Diferente de 07.02/07.08, esta tela (Settings.vue, fora do assistente
// InboxChannels.vue) NÃO tem a coluna de marca proibida — confirmado com
// scripts/central-de-ajuda/../diag (busca por "Chatwoot"/"Autonom" na
// página inteira não achou nada). Por isso os zooms aqui seguem o padrão
// do modelo (1,5–2×), sem as medições apertadas dos outros dois vídeos.
//
// "Atualizar" chama a API da própria plataforma (inboxMembers/create) —
// não é serviço de fora, então o clique final acontece de verdade.

export const id = '07.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nome com cara de uso real da corretora (não "teste"/"vídeo") — ele
// aparece no vídeo. Só esta caixa, por este nome, é nossa; nada mais na
// conta 9 é tocado.
const NOME_CAIXA_TESTE = 'WhatsApp Atendimento Sul';

// Cria (de novo, do zero) a caixa sem nenhum agente — o "antes" que o
// vídeo precisa mostrar. Idempotente: apaga a caixa anterior (só a nossa,
// pelo nome) antes de recriar. Não toca nas caixas de verdade da conta 9
// nem em nenhum agente existente.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA_TESTE)}
existente = conta.inboxes.find_by(name: nome)
existente&.destroy!
canal = Channel::Api.create!(account: conta, webhook_url: nil)
Inbox.create!(account: conta, name: nome, channel: canal)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    // Abertura fundida com a navegação (mesma razão de 07.08/07.02): a
    // página pousada após o login não é confiável.
    legenda: 'Colocar quem atende na caixa',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: NOME_CAIXA_TESTE,
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    // Clique pela posição na linha (não pelo texto do nome): o nome da
    // caixa fica num <span title="..."> sem clique próprio; quem navega é
    // o ícone de engrenagem — medido com diag.mjs dentro da linha certa
    // via :has(), pra não depender da ordem alfabética da lista.
    legenda: 'Abra a caixa de WhatsApp',
    acao: 'mover e clicar',
    alvo: {
      seletor: `div.flex.justify-between:has(span[title="${NOME_CAIXA_TESTE}"]) a`,
    },
    zoom: 2.2,
  },
  {
    legenda: 'Clique na aba Agentes',
    acao: 'mover e clicar',
    // A palavra "Agentes" também existe no menu lateral do produto — o
    // seletor por posição pega só a aba de dentro da caixa (2º item da
    // lista de abas desta tela).
    alvo: { seletor: '.settings ul li:nth-child(2) a' },
    zoom: 2.5,
  },
  {
    legenda: 'Digite o nome da pessoa',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Escolha agentes para a caixa de entrada"]',
    },
    texto: ['Bia'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique no nome dela',
    acao: 'mover e clicar',
    alvo: { texto: 'Bia Vendas' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar' },
    zoom: 2,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Agente atualizado com sucesso' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
];
