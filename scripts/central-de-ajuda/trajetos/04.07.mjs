// Roteiro do vídeo de trajeto do artigo 04.07 — "A regra que mais confunde:
// papel não dá acesso à caixa". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json.
//
// Trajeto: Configurações → Caixas de Entrada → escolha a caixa → aba
// Agentes → adicione a pessoa. Mesmo padrão de 07.03 (mesma tela,
// Settings.vue, sem marca), com uma caixa e um agente próprios deste
// vídeo pra não disputar dado com 07.03.
//
// "Atualizar" chama a API da própria plataforma — não é serviço de fora,
// o clique final acontece de verdade.

export const id = '04.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nome com cara de uso real da corretora — aparece no vídeo.
const NOME_CAIXA = 'WhatsApp Suporte Sul';

// Cria a caixa sem nenhum agente — o "antes" que o vídeo precisa mostrar.
// Idempotente: apaga a caixa anterior (só a nossa, pelo nome) antes de
// recriar. Não toca nas caixas de verdade da conta 9 nem em nenhum agente.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA)}
existente = conta.inboxes.find_by(name: nome)
existente&.destroy!
canal = Channel::Api.create!(account: conta, webhook_url: nil)
Inbox.create!(account: conta, name: nome, channel: canal)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Papel não dá acesso à caixa sozinho',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: NOME_CAIXA,
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    // Mesmo problema de texto de 07.03: o nome da caixa fica num <span
    // title="..."> sem clique próprio; quem navega é o ícone de
    // engrenagem, achado pela linha certa via :has().
    legenda: 'Abra a caixa',
    acao: 'mover e clicar',
    alvo: {
      seletor: `div.flex.justify-between:has(span[title="${NOME_CAIXA}"]) a`,
    },
    zoom: 2.2,
  },
  {
    legenda: 'Clique na aba Agentes',
    acao: 'mover e clicar',
    alvo: { seletor: '.settings ul li:nth-child(2) a' },
    zoom: 2.5,
  },
  {
    legenda: 'Digite o nome da pessoa',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Escolha agentes para a caixa de entrada"]',
    },
    texto: ['Caio'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique no nome dele',
    acao: 'mover e clicar',
    alvo: { texto: 'Caio Sinistro' },
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
