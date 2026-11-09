// #2692 — o que cada papel pode na tela nova. Na demonstração o papel vem do
// endereço (&papel=), para alternar sem trocar de usuário; fora dela, as
// permissões vêm da conta (useAcharPermissoes).
//   buscar: fazer busca nova e escolher quem vai (prospecting_manage)
//   funil: mandar para o funil (can_send_to_crm)
//   lista: "Guardar para mandar mensagem" (campaign_manage + jornada de Campanhas)
//   trocarDono: "Com quem fica · Alterar" (crm_manage_pipelines, #2694)
//   verTodas: "Ver buscas de todos" (mostra "Feita por" e "Achado por")
export const PAPEIS = [
  'dono',
  'gestora',
  'agente',
  'vendedor-sem-funil',
  'so-ver',
  'sem-campanha',
];

export const PAPEL_PADRAO = 'dono';

const TUDO = {
  buscar: true,
  funil: true,
  lista: true,
  trocarDono: true,
  verTodas: true,
};

const PERMISSOES = {
  dono: TUDO,
  gestora: TUDO,
  agente: { ...TUDO, lista: false, trocarDono: false, verTodas: false },
  'vendedor-sem-funil': {
    ...TUDO,
    funil: false,
    trocarDono: false,
    verTodas: false,
  },
  'so-ver': {
    buscar: false,
    funil: false,
    lista: false,
    trocarDono: false,
    verTodas: true,
  },
  'sem-campanha': { ...TUDO, lista: false },
};

// Estados da demonstração que já dizem o papel (v4: leitura, só Ver e vendedor
// sem funil). O &papel= do endereço, quando vem, vale mais.
const PAPEL_DO_ESTADO = {
  leitura: 'so-ver',
  'leitura-vazia': 'so-ver',
  'gaveta-leitura': 'so-ver',
  'buscas-so-ver': 'so-ver',
  'buscas-so-ver-vazio': 'so-ver',
  'fila-so-ver': 'so-ver',
  'fila-vazia-so-ver': 'so-ver',
  'fila-sem-funil': 'vendedor-sem-funil',
  'folha-funil-agente': 'agente',
  'folha-so-funil': 'sem-campanha',
  'folha-so-lista': 'vendedor-sem-funil',
};

export const papelValido = (papel, estado = null) => {
  if (PAPEIS.includes(papel)) return papel;
  return PAPEL_DO_ESTADO[estado] || PAPEL_PADRAO;
};

// "Apagar" só na busca de quem está logado, também para o administrador; o
// servidor recusa apagar a busca de outra pessoa (searches#destroy, #2693).
// Busca antiga sem dono (user_id vazio) ninguém apaga pela tela nova.
export const podeApagarBusca = ({ busca, usuarioId, demo }) => {
  if (busca.feitaPorId != null) return busca.feitaPorId === usuarioId;
  if (demo) return !busca.feitaPor;
  return false;
};

// A busca é de quem está vendo quando o dono (user_id) é ele; a demonstração
// usa a mesma regra (acharFonte dá o id do usuário às buscas dele).
export const ehMinha = (busca, usuarioId) =>
  busca.feitaPorId != null && busca.feitaPorId === usuarioId;

// Quem fez, para "Feita por": 'voce', o nome de outra pessoa, ou vazio quando
// a busca é antiga e não tem dono (aí a linha não aparece).
export const autorDaBusca = (busca, usuarioId) => {
  if (ehMinha(busca, usuarioId)) return 'voce';
  if (busca.feitaPorId == null) return '';
  return busca.feitaPor || '';
};

// As buscas que a pessoa vê na porta e em "Suas buscas": com "Ver buscas de
// todos" (verTodas), as da equipe; sem, só as dela.
export const buscasVisiveis = ({ buscas, usuarioId, verTodas }) =>
  verTodas ? buscas : buscas.filter(busca => ehMinha(busca, usuarioId));

// "Buscas da equipe" quando a pessoa vê as de todos e há alguma de outra
// pessoa; quem só vê está sempre na da equipe.
export const ehDaEquipe = ({ buscas, usuarioId, permissoes }) =>
  Boolean(permissoes.verTodas) &&
  (!permissoes.buscar || buscas.some(busca => !ehMinha(busca, usuarioId)));

export const permissoesDoPapel = papel => ({
  ...PERMISSOES[papelValido(papel)],
});
