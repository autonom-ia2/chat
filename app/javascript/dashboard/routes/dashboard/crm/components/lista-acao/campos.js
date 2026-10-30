// #2379 — "Mais → Escolher o que aparece": o que vai embaixo do nome, na
// coluna do meio. Cliente e Próximo passo ficam sempre. A escolha fica neste
// navegador, por funil (versão 2 das preferências da Lista).
export const CAMPOS = [
  'situacao',
  'etapa',
  'quem_cuida',
  'valor',
  'conversando',
  'novidade',
  'prioridade',
];
const VISIVEIS_DE_PADRAO = ['situacao', 'etapa', 'quem_cuida', 'valor'];

export const camposPadrao = () =>
  CAMPOS.map(chave => ({ chave, visivel: VISIVEIS_DE_PADRAO.includes(chave) }));

// Aceita só os campos conhecidos, uma vez cada; o que faltar entra no fim,
// escondido (campo novo não aparece sozinho para quem já escolheu).
export const normalizarCampos = lista => {
  if (!Array.isArray(lista) || !lista.length) return camposPadrao();
  const conhecidos = lista.reduce(
    (juntos, item) =>
      CAMPOS.includes(item?.chave) &&
      !juntos.some(campo => campo.chave === item.chave)
        ? [...juntos, { chave: item.chave, visivel: Boolean(item.visivel) }]
        : juntos,
    []
  );
  if (!conhecidos.length) return camposPadrao();
  const vistos = new Set(conhecidos.map(campo => campo.chave));
  return [
    ...conhecidos,
    ...CAMPOS.filter(chave => !vistos.has(chave)).map(chave => ({
      chave,
      visivel: false,
    })),
  ];
};

export const camposVisiveis = campos =>
  campos.filter(item => item.visivel).map(item => item.chave);

export const alternarCampo = (campos, chave) =>
  campos.map(item =>
    item.chave === chave ? { ...item, visivel: !item.visivel } : item
  );

// passo -1 sobe, +1 desce; nas pontas não faz nada.
export const moverCampo = (campos, chave, passo) => {
  const de = campos.findIndex(item => item.chave === chave);
  const para = de + passo;
  if (de < 0 || para < 0 || para >= campos.length) return campos;
  const nova = [...campos];
  [nova[de], nova[para]] = [nova[para], nova[de]];
  return nova;
};

// --- guardar no navegador -----------------------------------------------------
const CHAVE = 'crm_lista_acao_prefs:v2';
const chaveDoFunil = pipelineId => `${CHAVE}:${pipelineId || 'padrao'}`;

export const lerPreferencias = pipelineId => {
  try {
    const salvo = JSON.parse(
      window.localStorage.getItem(chaveDoFunil(pipelineId)) || '{}'
    );
    return { organizar: salvo.organizar, campos: salvo.campos };
  } catch {
    return {};
  }
};

export const guardarPreferencias = (pipelineId, preferencias) => {
  try {
    window.localStorage.setItem(
      chaveDoFunil(pipelineId),
      JSON.stringify(preferencias)
    );
  } catch {
    // Navegador sem armazenamento (aba anônima, cota): vale só nesta visita.
  }
};

// --- listas guardadas da Lista de sempre ----------------------------------------
// Coluna antiga → campo da Lista nova. Status, SLA, Meta, caixa e conversa não
// têm campo (o mockup tira essas colunas da Lista).
const DA_COLUNA_ANTIGA = {
  stage: 'etapa',
  owner: 'quem_cuida',
  value: 'valor',
  responsible: 'conversando',
  lastActivity: 'novidade',
  priority: 'prioridade',
};

const camposDasColunas = colunas => {
  const visivel = colunas?.columnVisibility || {};
  const ordem = colunas?.columnOrder?.length
    ? colunas.columnOrder
    : Object.keys(DA_COLUNA_ANTIGA);
  const daOrdem = ordem
    .filter(coluna => DA_COLUNA_ANTIGA[coluna])
    .map(coluna => ({
      chave: DA_COLUNA_ANTIGA[coluna],
      visivel:
        coluna in visivel
          ? visivel[coluna] !== false
          : VISIVEIS_DE_PADRAO.includes(DA_COLUNA_ANTIGA[coluna]),
    }));
  return normalizarCampos([{ chave: 'situacao', visivel: true }, ...daOrdem]);
};

export const camposDaLista = config => {
  if (config?.lista_acao?.campos)
    return normalizarCampos(config.lista_acao.campos);
  if (config?.columns) return camposDasColunas(config.columns);
  return null;
};
