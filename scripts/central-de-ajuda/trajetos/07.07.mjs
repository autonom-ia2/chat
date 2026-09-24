// Roteiro do vídeo de trajeto do artigo 07.07 — "A lista de caixas de
// entrada já criadas". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json e no
// componente routes/dashboard/settings/inbox/Index.vue.
//
// Trajeto: Configurações → Caixas de Entrada → busque pelo nome → clique
// numa caixa para abrir a configuração dela. Vídeo só de leitura/busca —
// nada é criado além da própria caixa de teste que dá conteúdo à lista
// (sem ela, a busca não teria o que filtrar).

export const id = '07.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_CAIXA = 'Cotação Rápida Centro';

// Idempotente: recria a caixa do zero — só existe pra dar à lista um nome
// bem distinto pra buscar. Só mexe na caixa que este vídeo cria.
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
    legenda: 'Veja as caixas já criadas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: NOME_CAIXA,
    zoom: 1,
    duracaoMs: 2800,
  },
  {
    legenda: 'Busque pelo nome ou canal',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Pesquisar por nome da caixa de entrada, canal ou identificador..."]',
    },
    texto: ['Cotação'],
    zoom: 1.6,
  },
  {
    legenda: 'A lista filtra na hora',
    acao: 'parar',
    alvo: { texto: NOME_CAIXA },
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    // Mesma técnica de 07.03/07.06/07.11: o nome fica num <span
    // title="..."> sem clique próprio; quem navega é o link da linha.
    legenda: 'Clique para abrir a caixa',
    acao: 'mover e clicar',
    alvo: {
      seletor: `div.flex.justify-between:has(span[title="${NOME_CAIXA}"]) a`,
    },
    zoom: 2,
    aguardarTextoDepois: 'Configurações',
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: NOME_CAIXA },
    zoom: 1.2,
    duracaoMs: 3000,
  },
];
