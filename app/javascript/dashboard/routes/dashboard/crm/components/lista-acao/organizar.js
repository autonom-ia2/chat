// #2379 — "Mais → Organizar por" da Lista nova. Uma escolha só; as três
// primeiras separam em grupos com o número de cada um (Etapa e Quem cuida
// somam o valor), as outras viram lista única. A ordem é do servidor
// (Crm::Cards::OrganizarPor): os grupos vêm inteiros e "Mostrar mais" continua
// de onde parou.
export const PADRAO = 'acao';
export const ORGANIZAR = [
  'acao',
  'etapa',
  'quem_cuida',
  'retorno',
  'valor',
  'parado',
  'nome',
];
// As que separam em grupos com cabeçalho; "acao" é a dos grupos de ação.
export const COM_GRUPOS = ['acao', 'etapa', 'quem_cuida'];
// A contagem de cada grupo: summaries?group_by=…
export const RESUMO = { etapa: 'stage', quem_cuida: 'quem_cuida' };

// "Maior valor" só para quem vê o valor de venda (#2075).
export const opcoesDeOrganizar = ({ podeVerValor }) =>
  ORGANIZAR.filter(opcao => opcao !== 'valor' || podeVerValor);

export const organizarValido = (organizar, { podeVerValor }) =>
  opcoesDeOrganizar({ podeVerValor }).includes(organizar) ? organizar : PADRAO;

// A mesma chave que o servidor dá ao grupo de "Quem cuida" ("agent:5",
// "bot:3"); ninguém cuidando é null.
export const chaveDeQuemCuida = card => {
  const quem = card.current_responsible;
  return quem?.type && quem.id != null ? `${quem.type}:${quem.id}` : null;
};

const calcularChave = (organizar, card) => {
  if (organizar === 'etapa') return String(card.stage_id ?? '');
  return chaveDeQuemCuida(card);
};

// Tempo real sem pular linha: o grupo é o da carga (`grupo_na_carga`, gravado
// quando a linha chega do servidor); a linha muda no lugar até "Atualizar".
export const comGrupoDaCarga = card => ({
  ...card,
  grupo_na_carga: {
    etapa: calcularChave('etapa', card),
    quem_cuida: calcularChave('quem_cuida', card),
  },
});

export const chaveDoGrupo = (organizar, card) => {
  const daCarga = card.grupo_na_carga;
  return daCarga && organizar in daCarga
    ? daCarga[organizar]
    : calcularChave(organizar, card);
};

// Contagem do servidor ({ groups: [{ key, count, sum_cents, currency, label }] })
// → { "chave": { conta, soma, moeda, rotulo } }. Ninguém cuidando fica em "".
export const resumoPorChave = resumo =>
  Object.fromEntries(
    (resumo?.groups || []).map(grupo => [
      grupo.key == null ? '' : String(grupo.key),
      {
        conta: Number(grupo.count) || 0,
        soma: grupo.sum_cents == null ? null : Number(grupo.sum_cents),
        moeda: grupo.currency || 'BRL',
        rotulo: grupo.label || '',
      },
    ])
  );

// --- listas guardadas ---------------------------------------------------------
// A Lista de sempre guarda { columns, filters, sort, group_by, density }. A
// Lista nova acrescenta `lista_acao` e escreve sort/group_by equivalentes, para a
// lista guardada abrir nas duas.
const DA_ORDEM_ANTIGA = {
  value: 'valor',
  title: 'nome',
  followUp: 'retorno',
  lastActivity: 'parado',
  enteredStage: 'parado',
};
const DO_AGRUPAR_ANTIGO = { stage: 'etapa', owner: 'quem_cuida' };

export const organizarDaLista = (config, { podeVerValor }) => {
  const salvo = config?.lista_acao?.organizar;
  const antigo =
    DO_AGRUPAR_ANTIGO[config?.group_by] || DA_ORDEM_ANTIGA[config?.sort?.id];
  return organizarValido(salvo || antigo || PADRAO, { podeVerValor });
};

const PARA_A_LISTA_ANTIGA = {
  acao: { sort: null, group_by: 'none' },
  etapa: { sort: null, group_by: 'stage' },
  quem_cuida: { sort: null, group_by: 'owner' },
  retorno: { sort: { id: 'followUp', desc: false }, group_by: 'none' },
  valor: { sort: { id: 'value', desc: true }, group_by: 'none' },
  parado: { sort: { id: 'lastActivity', desc: false }, group_by: 'none' },
  nome: { sort: { id: 'title', desc: false }, group_by: 'none' },
};

export const configDaLista = ({ base, organizar, campos }) => ({
  ...base,
  ...PARA_A_LISTA_ANTIGA[organizar],
  lista_acao: { versao: 1, organizar, campos },
});
