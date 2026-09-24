// Roteiro do vídeo de trajeto do artigo 05.04 — "Excluir um time sem
// perder conversa". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/teamsSettings.json
// (TEAMS_SETTINGS.DELETE).
//
// Trajeto: Configurações → Times → pesquisar → ícone de lixeira → digitar o
// nome do time (minúsculo) para confirmar → Excluir.
//
// O time que é excluído nasce pelo `preparar` (regra do lote: 05.04 cria o
// time que vai ser excluído pelo preparar) — nunca mexe em "vendas",
// "sinistro" ou "vendas sul".

export const id = '05.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_TIME = 'Suporte Temporário Norte';

// Idempotente: recria o time a cada gravação, para a exclusão ter sempre
// algo de verdade para apagar.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_TIME)}
conta.teams.where(name: nome.downcase).destroy_all
conta.teams.create!(name: nome, description: "Reforço de atendimento no lançamento da campanha de Norte")
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Excluir um time sem perder conversa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações → Times',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/teams/list`,
    aguardarTexto: 'Times',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Pesquise pelo nome do time',
    acao: 'mover e clicar',
    alvo: { seletor: 'input[placeholder="Pesquisar times..."]' },
    zoom: 1.8,
  },
  {
    legenda: 'Digite o nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar times..."]' },
    texto: ['Suporte Temporário'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique na lixeira do time',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-woot-bin"]' },
    zoom: 1.8,
    aguardarTextoDepois: 'exclusão do time',
  },
  {
    legenda: 'Digite o nome do time para confirmar',
    acao: 'digitar',
    alvo: { seletor: 'input[type="text"]' },
    texto: [NOME_TIME.toLowerCase()],
    zoom: 1.6,
  },
  {
    legenda: 'Confirme a exclusão',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[type="submit"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
