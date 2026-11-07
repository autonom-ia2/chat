// #2692 — o que cada papel pode na tela nova. Na demonstração o papel vem do
// endereço (&papel=), para alternar sem trocar de usuário; fora dela, as
// permissões vêm da conta (useAcharPermissoes).
//   buscar: fazer busca nova e escolher quem vai (prospecting_manage)
//   funil: mandar para o funil (can_send_to_crm)
//   lista: "Guardar para mandar mensagem" (campaign_manage + jornada de Campanhas)
//   trocarDono: "Com quem fica · Alterar" (caso A, decisão do Rodrigo pendente)
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

export const permissoesDoPapel = papel => ({
  ...PERMISSOES[papelValido(papel)],
});
