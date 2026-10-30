import {
  grupoDoResultado,
  nomeDe,
  nomeDoCorte,
  marcoMaisLonge,
  pct,
} from './desempenhoContrato';

// #2226 v2 — lógica pura da aba Detalhe: filtro, busca, ordenação, paginação, total do período e
// a ida e volta entre os filtros e o endereço. Nada aqui lê a tela; os componentes só desenham.

export const TABELAS = ['procuras', 'periodo', 'tema', 'ativas', 'regras'];
export const TABELA_PADRAO = 'procuras';
export const TAMANHOS_DE_PAGINA = [25, 50, 100];
export const TAMANHO_PADRAO = 25;
// Os 4 valores de qualidade são universais (não dependem do negócio).
export const QUALIDADES = ['acertou', 'erro_leve', 'erro_grave', 'nao_atuou'];
export const GRUPOS = [
  'fechou',
  'avancou',
  'parou',
  'resolveu',
  'passou',
  'sem_negocio',
];
// Prefixos do valor do filtro de resultado: um grupo inteiro ou um resultado só.
const PREFIXO_GRUPO = 'grupo:';
const PREFIXO_ITEM = 'item:';
// Separador do filtro de corte no endereço: "<corte>:<valor>".
const SEPARADOR_CORTE = ':';

export const FILTROS_VAZIOS = Object.freeze({
  busca: '',
  tema: '',
  resultado: '',
  marco: '',
  qualidade: '',
  origem: '',
  corte: '',
  perda: false,
  pessoa: false,
  testes: false,
});

const CHAVES_DE_TEXTO = [
  'busca',
  'tema',
  'resultado',
  'marco',
  'qualidade',
  'origem',
  'corte',
];
const CHAVES_LIGA_DESLIGA = ['perda', 'pessoa', 'testes'];
// No endereço, o filtro de origem se chama `veio_de`: `origem` é da página (`origem=webhook`, o robô de outro
// sistema). Com o mesmo nome, trocar de tabela apagava o `origem=webhook` e o painel pedia o agente errado (#2251).
const NO_ENDERECO = { origem: 'veio_de' };
const noEndereco = chave => NO_ENDERECO[chave] || chave;
// Tudo o que a aba Detalhe põe no endereço (a página guarda aba, período e origem).
export const CHAVES_DO_ENDERECO = [
  'tabela',
  ...CHAVES_DE_TEXTO.map(noEndereco),
  ...CHAVES_LIGA_DESLIGA,
  'pagina',
  'tamanho',
];

// Faixa dos acentos combinantes depois do NFD (U+0300 a U+036F).
const ACENTO_INICIO = 0x300;
const ACENTO_FIM = 0x36f;

// Texto comparável: sem acento e sem diferença de maiúscula. Sem regex (regra do Rodrigo).
export const textoDeBusca = texto =>
  Array.from(String(texto ?? '').normalize('NFD'))
    .filter(letra => {
      const codigo = letra.codePointAt(0);
      return codigo < ACENTO_INICIO || codigo > ACENTO_FIM;
    })
    .join('')
    .toLocaleLowerCase()
    .trim();

const primeiro = valor => (Array.isArray(valor) ? valor[0] : valor);
const textoDoEndereco = valor => {
  const bruto = primeiro(valor);
  return bruto === undefined || bruto === null ? '' : String(bruto);
};
const ligadoNoEndereco = valor => textoDoEndereco(valor) === '1';
const inteiroPositivo = (valor, padrao) => {
  const numero = Number.parseInt(textoDoEndereco(valor), 10);
  return Number.isFinite(numero) && numero > 0 ? numero : padrao;
};

export const algumFiltroLigado = filtros =>
  CHAVES_DE_TEXTO.some(chave => Boolean(filtros[chave])) ||
  CHAVES_LIGA_DESLIGA.some(chave => Boolean(filtros[chave]));

// O marco conta como alcançado quando a procura chegou a ele ou a uma etapa depois (regra do
// funil). Uma etapa pode juntar mais de um marco (`etapa.marcos`). Fora do funil, vale a presença.
const marcosDaEtapa = etapa =>
  Array.isArray(etapa.marcos) && etapa.marcos.length
    ? etapa.marcos
    : [etapa.id];
const alcancouMarco = (procura, marco, etapas) => {
  const marcos = procura.marcos || [];
  if (marcos.includes(marco)) return true;
  const posicao = etapas.findIndex(
    etapa => etapa.id === marco || marcosDaEtapa(etapa).includes(marco)
  );
  if (posicao < 0) return false;
  return etapas
    .slice(posicao)
    .some(etapa => marcosDaEtapa(etapa).some(id => marcos.includes(id)));
};

const casaResultado = (procura, filtro, catalogo) => {
  if (filtro.startsWith(PREFIXO_GRUPO))
    return (
      grupoDoResultado(catalogo, procura.resultado_id) ===
      filtro.slice(PREFIXO_GRUPO.length)
    );
  if (filtro.startsWith(PREFIXO_ITEM))
    return procura.resultado_id === filtro.slice(PREFIXO_ITEM.length);
  return procura.resultado_id === filtro;
};

const casaCorte = (procura, filtro) => {
  const posicao = filtro.indexOf(SEPARADOR_CORTE);
  if (posicao < 0) return true;
  const corte = filtro.slice(0, posicao);
  const valor = filtro.slice(posicao + 1);
  return (procura.cortes || {})[corte] === valor;
};

const casaBusca = (procura, busca, catalogo) => {
  if (!busca) return true;
  const alvo = [
    procura.resumo,
    String(procura.conversa),
    `#${procura.conversa}`,
    nomeDe(catalogo, 'temas', procura.tema_id),
  ]
    .map(textoDeBusca)
    .join(' ');
  return alvo.includes(busca);
};

// Uma regra por filtro; todas precisam passar. Testes ficam fora, a não ser que peçam.
export function filtrarProcuras(procuras, filtros, catalogo, etapas = []) {
  const f = { ...FILTROS_VAZIOS, ...filtros };
  const busca = textoDeBusca(f.busca);
  return (procuras || []).filter(
    procura =>
      (f.testes || !procura.teste) &&
      (!f.tema || procura.tema_id === f.tema) &&
      (!f.resultado || casaResultado(procura, f.resultado, catalogo)) &&
      (!f.marco || alcancouMarco(procura, f.marco, etapas)) &&
      (!f.qualidade || procura.qualidade_id === f.qualidade) &&
      (!f.origem || procura.origem_id === f.origem) &&
      (!f.corte || casaCorte(procura, f.corte)) &&
      (!f.perda || procura.perda_evitavel) &&
      (!f.pessoa || procura.precisava_pessoa) &&
      casaBusca(procura, busca, catalogo)
  );
}

const vazio = valor => valor === null || valor === undefined || valor === '';

const comparar = (a, b) => {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  return String(a).localeCompare(String(b), undefined, {
    numeric: true,
    sensitivity: 'base',
  });
};

// Ordena uma cópia. Valor vazio fica sempre no fim, nos dois sentidos; empate mantém a ordem.
export function ordenar(linhas, ordem) {
  const lista = [...(linhas || [])];
  if (!ordem?.coluna) return lista;
  const sinal = ordem.sentido === 'desc' ? -1 : 1;
  return lista
    .map((linha, indice) => ({ linha, indice }))
    .sort((x, y) => {
      const a = x.linha[ordem.coluna];
      const b = y.linha[ordem.coluna];
      if (vazio(a) && vazio(b)) return x.indice - y.indice;
      if (vazio(a)) return 1;
      if (vazio(b)) return -1;
      return sinal * comparar(a, b) || x.indice - y.indice;
    })
    .map(({ linha }) => linha);
}

// Fatia a página pedida; página fora do alcance volta para a mais próxima.
export function paginar(linhas, pagina, tamanho) {
  const total = (linhas || []).length;
  const porPagina = tamanho > 0 ? tamanho : TAMANHO_PADRAO;
  const paginas = Math.max(1, Math.ceil(total / porPagina));
  const atual = Math.min(Math.max(1, pagina || 1), paginas);
  const comeco = (atual - 1) * porPagina;
  const itens = (linhas || []).slice(comeco, comeco + porPagina);
  return {
    itens,
    pagina: atual,
    paginas,
    total,
    de: total ? comeco + 1 : 0,
    ate: comeco + itens.length,
  };
}

const CAMPOS_DO_PERIODO = [
  'procuras',
  'conversas_novas',
  'compra',
  'fecharam',
  'precisavam_pessoa',
  'tiveram_pessoa',
  'com_anuncio',
  'sem_anuncio',
];

// A linha "Total do período": soma de cada coluna e a taxa de fechamento sobre a soma.
export function totalDoPeriodo(pontos) {
  const soma = Object.fromEntries(
    CAMPOS_DO_PERIODO.map(campo => [
      campo,
      (pontos || []).reduce((total, ponto) => total + (ponto[campo] || 0), 0),
    ])
  );
  return { ...soma, taxa_pct: pct(soma.fecharam, soma.compra) };
}

const opcao = (value, label) => ({ value, label });
const ordemDoCatalogo = (catalogo, tipo) =>
  Object.keys(catalogo?.[tipo] || {}).map(id =>
    opcao(id, nomeDe(catalogo, tipo, id))
  );

const T = 'AGENTS.DESEMPENHO2.B.FILTROS';

// Opções de todos os filtros, prontas para o ChoiceSelect. Os nomes vêm do catálogo (dado); só a
// moldura ("Todos", nomes dos grupos e da qualidade) vem do i18n.
export function opcoesDosFiltros(painel, t) {
  const catalogo = painel?.catalogo || {};
  const todos = opcao('', t(`${T}.TODOS`));
  const nomeDoGrupo = grupo =>
    grupo === 'fechou' && painel?.meta?.nomes?.fechou
      ? painel.meta.nomes.fechou
      : t(`${T}.GRUPO.${grupo.toUpperCase()}`);
  const resultados = Object.entries(catalogo.resultados || {});
  const gruposDoResultado = GRUPOS.filter(grupo =>
    resultados.some(([, item]) => item.grupo === grupo)
  ).map(grupo => ({
    label: nomeDoGrupo(grupo),
    options: [
      opcao(
        `${PREFIXO_GRUPO}${grupo}`,
        t(`${T}.TODO_O_GRUPO`, { grupo: nomeDoGrupo(grupo) })
      ),
      ...resultados
        .filter(([, item]) => item.grupo === grupo)
        .map(([id]) =>
          opcao(`${PREFIXO_ITEM}${id}`, nomeDe(catalogo, 'resultados', id))
        ),
    ],
  }));
  const gruposDoCorte = (painel?.cortes || []).map(corte => ({
    label: corte.nome,
    options: Object.keys(catalogo.cortes?.[corte.id] || {}).map(valor =>
      opcao(
        `${corte.id}${SEPARADOR_CORTE}${valor}`,
        nomeDoCorte(catalogo, corte.id, valor)
      )
    ),
  }));
  return {
    temas: [todos, ...ordemDoCatalogo(catalogo, 'temas')],
    resultados: [{ label: '', options: [todos] }, ...gruposDoResultado],
    marcos: [todos, ...ordemDoCatalogo(catalogo, 'marcos')],
    qualidades: [
      todos,
      ...QUALIDADES.map(id =>
        opcao(id, t(`${T}.QUALIDADE.${id.toUpperCase()}`))
      ),
    ],
    origens: [todos, ...ordemDoCatalogo(catalogo, 'origens')],
    cortes: [
      { label: '', options: [todos] },
      ...gruposDoCorte.filter(g => g.options.length),
    ],
  };
}

const valoresDe = lista =>
  lista
    .flatMap(item => (item.options ? item.options : [item]))
    .map(o => o.value);

// Valor que não existe nas opções (endereço antigo, outro período) vira "Todos": assim nenhum
// filtro invisível esvazia a tabela.
export function filtrosValidos(filtros, opcoes) {
  const permitidos = {
    tema: valoresDe(opcoes.temas),
    resultado: valoresDe(opcoes.resultados),
    marco: valoresDe(opcoes.marcos),
    qualidade: valoresDe(opcoes.qualidades),
    origem: valoresDe(opcoes.origens),
    corte: valoresDe(opcoes.cortes),
  };
  return Object.fromEntries(
    Object.entries(filtros).map(([chave, valor]) => [
      chave,
      permitidos[chave] && !permitidos[chave].includes(valor) ? '' : valor,
    ])
  );
}

export function filtrosDoEndereco(query = {}) {
  const tamanho = inteiroPositivo(query.tamanho, TAMANHO_PADRAO);
  return {
    ...Object.fromEntries(
      CHAVES_DE_TEXTO.map(chave => [
        chave,
        textoDoEndereco(query[noEndereco(chave)]),
      ])
    ),
    ...Object.fromEntries(
      CHAVES_LIGA_DESLIGA.map(chave => [chave, ligadoNoEndereco(query[chave])])
    ),
    pagina: inteiroPositivo(query.pagina, 1),
    tamanho: TAMANHOS_DE_PAGINA.includes(tamanho) ? tamanho : TAMANHO_PADRAO,
  };
}

// Só o que difere do padrão vai para o endereço, para o link ficar curto.
export function enderecoDosFiltros(filtros) {
  const query = {};
  CHAVES_DE_TEXTO.forEach(chave => {
    const valor = String(filtros[chave] ?? '');
    if (valor.trim()) query[noEndereco(chave)] = valor;
  });
  CHAVES_LIGA_DESLIGA.forEach(chave => {
    if (filtros[chave]) query[chave] = '1';
  });
  if (filtros.pagina > 1) query.pagina = String(filtros.pagina);
  if (filtros.tamanho && filtros.tamanho !== TAMANHO_PADRAO)
    query.tamanho = String(filtros.tamanho);
  return query;
}

export const tabelaDoEndereco = query => {
  const tabela = textoDoEndereco(query?.tabela);
  return TABELAS.includes(tabela) ? tabela : TABELA_PADRAO;
};

// O endereço novo: o que a aba Detalhe não controla (aba, período, demo…) fica como está.
export function enderecoDaAba(queryAtual, tabela, filtros) {
  const resto = Object.fromEntries(
    Object.entries(queryAtual || {}).filter(
      ([chave]) => !CHAVES_DO_ENDERECO.includes(chave)
    )
  );
  const daTabela = tabela === TABELA_PADRAO ? {} : { tabela };
  const dosFiltros = tabela === 'procuras' ? enderecoDosFiltros(filtros) : {};
  return { ...resto, ...daTabela, ...dosFiltros };
}

// Uma linha de procura pronta para a tabela: nomes do catálogo e campos de ordenação.
export function linhaDaProcura(procura, painel) {
  const catalogo = painel?.catalogo || {};
  const etapas = painel?.funil?.etapas || [];
  const primeiroCorte = painel?.cortes?.[0]?.id;
  const marco = marcoMaisLonge(etapas, procura.marcos || []);
  return {
    chave: `${procura.conversa}-${procura.procura}`,
    inicio: procura.inicio,
    conversa: procura.conversa,
    procura: procura.procura,
    visivel: procura.visivel !== false,
    teste: Boolean(procura.teste),
    tema: nomeDe(catalogo, 'temas', procura.tema_id),
    pedido: primeiroCorte
      ? nomeDoCorte(catalogo, primeiroCorte, procura.cortes?.[primeiroCorte])
      : null,
    marco: marco ? nomeDe(catalogo, 'marcos', marco) : null,
    marco_ordem: marco ? etapas.findIndex(etapa => etapa.id === marco) : -1,
    resultado: nomeDe(catalogo, 'resultados', procura.resultado_id),
    grupo: grupoDoResultado(catalogo, procura.resultado_id),
    qualidade: procura.qualidade_id || null,
    origem: nomeDe(catalogo, 'origens', procura.origem_id),
    resumo: procura.resumo || '',
  };
}

// O contador acima da tabela: quantas procuras e quantas fecharam.
// A taxa usa a mesma base do funil: só as procuras que eram pedido de compra (`compra`). Procura
// sem o campo (contrato antigo) conta como compra.
export function resumoDasProcuras(procuras, catalogo) {
  const total = procuras.length;
  const deCompra = procuras.filter(procura => procura.compra !== false);
  const fecharam = deCompra.filter(
    procura => grupoDoResultado(catalogo, procura.resultado_id) === 'fechou'
  ).length;
  return {
    total,
    compra: deCompra.length,
    fecharam,
    pct: pct(fecharam, deCompra.length),
  };
}
