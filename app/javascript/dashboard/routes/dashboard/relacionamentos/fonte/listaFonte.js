import {
  ABAS,
  GRUPO_PADRAO,
  empresaPertenceAoGrupo,
  gruposDaAba,
  pertenceAoGrupo,
} from './grupos';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { normalizado, soDigitos } from './texto';
import { DEMO_CARREGANDO, esperarParaSempre } from './modoDemo';
import { SEM_ACESSO } from '../lista/falhas';
import { pessoaPassaNosFiltros, preenchido } from '../lista/filtros';

// #2894 — de onde a lista de Relacionamentos lê (molde:
// autonomia/prospecting/achar/utils/acharFonte.js). A tela recebe sempre o mesmo
// formato, venha de onde vier:
//   1. fonte real: as leituras do servidor (dashboard/api/relacionamentos.js).
//      Erro do servidor (422, 500) sobe como veio: a tela mostra o erro com
//      "tentar de novo". Quem não pode ver (401, 403) recebe a falha de nome
//      `SEM_ACESSO`: a tela diz que a pessoa não tem acesso, sem o botão;
//   2. demonstração: com `?demo=<estado>` (modoDemo.js) e só no ambiente de
//      desenvolvimento. Os dados são inventados (demo/base.js) e nada é gravado.
// O `import.meta.env.DEV` vira `false` no build de produção: o ramo some e a
// base fictícia nem entra no pacote.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/base.js')
  : null;

export const POR_PAGINA = 25;
export const ATRASO_DA_DEMO_MS = 300;
const PRIMEIRA_PAGINA = 1;

export const ORDENS = {
  ULTIMA_CONVERSA: 'ultima_conversa',
  NOME: 'nome',
  MAIS_NOVOS: 'mais_novos',
};
const LOCALE_DA_ORDEM_ALFABETICA = 'pt-BR';

const BASE_VAZIA = { pessoas: () => [], empresas: () => [] };

export const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

export const erroFonteRealPendente = () =>
  Object.assign(
    new Error('A fonte real de Relacionamentos ainda não existe.'),
    {
      name: 'FONTE_REAL_PENDENTE',
    }
  );

// ---- busca -----------------------------------------------------------------

const temLetra = texto => [...texto].some(char => char >= 'a' && char <= 'z');

const textoContem = (campos, termo) =>
  campos.some(campo => normalizado(campo).includes(termo));

const digitosContem = (campos, digitos) =>
  campos.some(campo => soDigitos(campo).includes(digitos));

// Letras buscam em nome, e-mail e empresa; só número busca em telefone e
// documento (com ou sem pontuação).
const combinaComBusca = (busca, { textos, numeros }) => {
  const termo = normalizado(busca);
  if (!termo) return true;
  if (temLetra(termo)) return textoContem(textos, termo);
  const digitos = soDigitos(termo);
  return digitos ? digitosContem(numeros, digitos) : false;
};

const camposDaPessoa = pessoa => ({
  textos: [
    pessoa.name,
    pessoa.email,
    pessoa.additional_attributes?.company_name,
  ],
  numeros: [pessoa.phone_number, pessoa.custom_attributes?.cpf],
});

const camposDaEmpresa = empresa => ({
  textos: [empresa.name, empresa.domain],
  numeros: [empresa.cnpj],
});

// ---- ordem -----------------------------------------------------------------

const maisRecentePrimeiro = campo => (a, b) => {
  const x = a[campo];
  const y = b[campo];
  if (x === null || x === undefined) {
    return y === null || y === undefined ? 0 : 1;
  }
  if (y === null || y === undefined) return -1;
  return y - x;
};

const porNome = (a, b) =>
  a.name.localeCompare(b.name, LOCALE_DA_ORDEM_ALFABETICA);

const ORDENADORES = {
  [ORDENS.ULTIMA_CONVERSA]: maisRecentePrimeiro('last_activity_at'),
  [ORDENS.NOME]: porNome,
  [ORDENS.MAIS_NOVOS]: maisRecentePrimeiro('created_at'),
};

// ---- demonstração ----------------------------------------------------------

const REGRAS_DA_ABA = {
  [ABAS.PESSOAS]: {
    daBase: (base, agora) => base.pessoas(agora),
    pertence: pertenceAoGrupo,
    campos: camposDaPessoa,
  },
  [ABAS.EMPRESAS]: {
    daBase: (base, agora) => base.empresas(agora),
    pertence: empresaPertenceAoGrupo,
    campos: camposDaEmpresa,
  },
};

const regrasDaAba = aba => REGRAS_DA_ABA[aba] || REGRAS_DA_ABA[ABAS.PESSOAS];

// O que a busca e os filtros deixam passar, antes de olhar o grupo. A lista e as
// contagens das pílulas usam esta mesma conta, para os números baterem.
const passaNaConsulta = (aba, { busca = '', filtros = {} }, agora) => {
  const regras = regrasDaAba(aba);
  return item =>
    combinaComBusca(busca, regras.campos(item)) &&
    (aba !== ABAS.PESSOAS || pessoaPassaNosFiltros(item, filtros, agora));
};

const fonteDemo = ({ estado, carregarDemo, atraso }) => {
  const baseDaDemo = async () => {
    // `?demo=carregando`: a fonte nunca responde, para o print do esqueleto.
    if (estado === DEMO_CARREGANDO) return esperarParaSempre();
    await esperar(atraso);
    return estado === 'vazio' ? BASE_VAZIA : carregarDemo();
  };
  const contarGrupo = (lista, regras, grupoId, agora) =>
    lista.filter(item => regras.pertence(item, grupoId, agora)).length;

  const achar = async ({
    aba = ABAS.PESSOAS,
    grupo = GRUPO_PADRAO[aba],
    busca = '',
    ordem = ORDENS.ULTIMA_CONVERSA,
    filtros = {},
  }) => {
    const agora = Date.now();
    const regras = regrasDaAba(aba);
    const ordenador = ORDENADORES[ordem] || ORDENADORES[ORDENS.ULTIMA_CONVERSA];
    return regras
      .daBase(await baseDaDemo(), agora)
      .filter(item => regras.pertence(item, grupo || GRUPO_PADRAO[aba], agora))
      .filter(passaNaConsulta(aba, { busca, filtros }, agora))
      .sort(ordenador);
  };

  return {
    usaDemo: true,
    async resumo() {
      const agora = Date.now();
      const base = await baseDaDemo();
      const gente = base.pessoas(agora);
      const regras = REGRAS_DA_ABA[ABAS.PESSOAS];
      const empresas = base.empresas(agora);
      const regrasDeEmpresa = REGRAS_DA_ABA[ABAS.EMPRESAS];
      return {
        empresas: {
          total: empresas.length,
          sem_conversa_3_meses: contarGrupo(
            empresas,
            regrasDeEmpresa,
            'sem_conversa_3_meses',
            agora
          ),
        },
        total: gente.length,
        clientes: contarGrupo(gente, regras, 'clientes', agora),
        sumiu_1_a_3_meses: contarGrupo(
          gente,
          regras,
          'sumiu_1_a_3_meses',
          agora
        ),
      };
    },
    // O número de cada pílula. Com `busca` e `filtros`, conta só quem combina
    // com eles: o número bate com a lista que a pessoa vê.
    async contagens(aba, consulta = {}) {
      const agora = Date.now();
      const regras = regrasDaAba(aba);
      const lista = regras
        .daBase(await baseDaDemo(), agora)
        .filter(passaNaConsulta(aba, consulta, agora));
      return Object.fromEntries(
        gruposDaAba(aba).map(grupo => [
          grupo.id,
          contarGrupo(lista, regras, grupo.id, agora),
        ])
      );
    },
    async listar(pedido = {}) {
      const { pagina = PRIMEIRA_PAGINA } = pedido;
      const achados = await achar(pedido);
      const inicio = (pagina - PRIMEIRA_PAGINA) * POR_PAGINA;
      return {
        itens: achados.slice(inicio, inicio + POR_PAGINA),
        total: achados.length,
        temMais: inicio + POR_PAGINA < achados.length,
      };
    },
    // Todos os que a consulta acha, sem paginar ("Marcar todas as 42").
    async listarTodos(pedido = {}) {
      const achados = await achar(pedido);
      return { itens: achados, total: achados.length };
    },
    // O que a gaveta "Mais filtros" oferece: só o que existe na base.
    async opcoesDeFiltro() {
      const base = await baseDaDemo();
      const gente = base.pessoas(Date.now());
      const unicos = lista => [...new Set(lista.filter(Boolean))].sort();
      const comoOpcao = valor => ({ value: valor, label: valor });
      return {
        empresas: base
          .empresas(Date.now())
          .map(({ id, name }) => ({ value: id, label: name }))
          .sort((a, b) => porNome({ name: a.label }, { name: b.label })),
        etiquetas: unicos(gente.flatMap(p => p.labels || [])).map(comoOpcao),
        cidades: unicos(gente.map(p => p.additional_attributes?.city)).map(
          comoOpcao
        ),
      };
    },
  };
};

// ---- fonte real ------------------------------------------------------------

// Grupo, ordem e período de chegada têm o mesmo nome na tela e no servidor. Só
// este filtro muda: a tela diz `chegouEm`, o servidor `chegou_em`.
const FILTRO_NO_SERVIDOR = {
  empresa: 'empresa',
  etiqueta: 'etiqueta',
  cidade: 'cidade',
  chegouEm: 'chegou_em',
};

const filtrosDoPedido = (filtros = {}) =>
  Object.entries(FILTRO_NO_SERVIDOR).map(([daTela, doServidor]) => [
    `filtros[${doServidor}]`,
    filtros[daTela],
  ]);

// O que vai na URL: só o que está preenchido. `filtros` é só de Pessoas: em
// Empresas o servidor responde 422 para qualquer filtro, então nunca vai.
const paramsDoPedido = ({ aba, grupo, busca, ordem, pagina, filtros }) =>
  Object.fromEntries(
    [
      ['grupo', grupo],
      ['busca', busca],
      ['ordem', ordem],
      ['pagina', pagina],
      ...(aba === ABAS.EMPRESAS ? [] : filtrosDoPedido(filtros)),
    ].filter(([, valor]) => preenchido(valor))
  );

// O servidor responde 401 quando a permissão de ver recusa (e sem sessão) e
// 403 quando Empresas está desligada na conta: nos dois a pessoa não pode ver.
const STATUS_SEM_ACESSO = [401, 403];

const erroSemAcesso = causa =>
  Object.assign(new Error('Sem acesso a Relacionamentos.', { cause: causa }), {
    name: SEM_ACESSO,
  });

// Toda leitura do servidor passa por aqui: a recusa por falta de acesso ganha
// nome; qualquer outro erro sobe como veio.
const doServidor = async pedido => {
  try {
    return (await pedido).data;
  } catch (falha) {
    throw STATUS_SEM_ACESSO.includes(falha?.response?.status)
      ? erroSemAcesso(falha)
      : falha;
  }
};

const fonteReal = () => ({
  usaDemo: false,
  async resumo() {
    return doServidor(RelacionamentosAPI.resumo());
  },
  async contagens(aba, { busca, filtros } = {}) {
    const params = paramsDoPedido({ aba, busca, filtros });
    return doServidor(
      aba === ABAS.EMPRESAS
        ? RelacionamentosAPI.contagensDeEmpresas(params)
        : RelacionamentosAPI.contagensDePessoas(params)
    );
  },
  async listar(pedido = {}) {
    const params = paramsDoPedido(pedido);
    const data = await doServidor(
      pedido.aba === ABAS.EMPRESAS
        ? RelacionamentosAPI.empresas(params)
        : RelacionamentosAPI.pessoas(params)
    );
    return { itens: data.itens, total: data.total, temMais: data.tem_mais };
  },
  // "Marcar todas as N" só existe em Pessoas. De cada uma vem só o que as ações
  // em grupo leem: id, nome, telefone, bloqueio e se pediu para não receber.
  async listarTodos(pedido = {}) {
    const params = paramsDoPedido({ ...pedido, pagina: undefined });
    return doServidor(RelacionamentosAPI.todasAsPessoas(params));
  },
  async opcoesDeFiltro() {
    return doServidor(RelacionamentosAPI.opcoesDeFiltro());
  },
});

export const listaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, carregarDemo, atraso })
    : fonteReal();
