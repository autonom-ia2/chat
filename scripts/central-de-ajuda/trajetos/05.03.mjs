// Roteiro do vídeo de trajeto do artigo 05.03 — "Editar um time: detalhes e
// membros". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/teamsSettings.json
// (TEAMS_SETTINGS.EDIT_FLOW, TEAMS_SETTINGS.FORM).
//
// Trajeto: Configurações → Times → pesquisar → ícone de engrenagem →
// Detalhes do time (editar nome/descrição) → Atualizar time → Alterar
// agentes → marcar uma pessoa → Atualizar agentes no time → Finalizar.
//
// Time próprio, criado pelo preparar — nunca mexe em "vendas", "sinistro"
// ou "vendas sul" (times reais/de outros vídeos).

export const id = '05.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_TIME = 'Atendimento Norte';

// Idempotente: recria o time do zero a cada gravação (mesmo nome, sem
// membros) — assim a cena de marcar uma pessoa sempre parte do mesmo
// estado.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_TIME)}
conta.teams.where(name: nome.downcase).destroy_all
conta.teams.create!(name: nome, description: "Atendimento da regional Norte")
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Editar um time: detalhes e membros',
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
    texto: ['Atendimento Norte'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique na engrenagem do time',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-woot-settings"]' },
    zoom: 1.8,
    aguardarTextoDepois: 'Nome do Time',
  },
  {
    legenda: 'Ajuste a descrição do time',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Breve descrição sobre este time."]' },
    limparAntes: true,
    texto: ['Atendimento comercial e sinistro da regional Norte'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar time',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[type="submit"]' },
    zoom: 1.8,
    aguardarTextoDepois: 'Adicionar agentes ao time',
  },
  {
    legenda: 'Marque uma pessoa para o time',
    acao: 'mover e clicar',
    alvo: { seletor: 'tbody tr:nth-child(1) input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar agentes no time',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar agentes no time' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
