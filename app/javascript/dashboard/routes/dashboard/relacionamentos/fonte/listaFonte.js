import { toValue } from 'vue';
import {
  ABAS,
  GRUPO_PADRAO,
  empresaPertenceAoGrupo,
  gruposDaAba,
  pertenceAoGrupo,
} from './grupos';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';
import { normalizado, soDigitos } from './texto';
import {
  DEMO_CARREGANDO,
  DEMO_SEM_SEGUROS,
  esperarParaSempre,
} from './modoDemo';
import { doServidor } from './doServidor';
import {
  FILTROS_DAS_EMPRESAS,
  empresaPassaNosFiltros,
  pessoaPassaNosFiltros,
  preenchido,
} from '../lista/filtros';
import { paraOServidor } from '../lista/informacoes';

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
// #2897 — a carteira fictícia na lista de pessoas da demonstração (o grupo
// "Só tem um seguro" e a busca pelos seguros). Fora da demonstração quem faz
// isso é o servidor, na mesma leitura da lista.
const CARREGAR_CARTEIRA = import.meta.env.DEV
  ? () => import('../demo/carteiraNaLista.js')
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

// ---- busca -----------------------------------------------------------------

const temLetra = texto => [...texto].some(char => char >= 'a' && char <= 'z');

const textoContem = (campos, termo) =>
  campos.some(campo => normalizado(campo).includes(termo));

const digitosContem = (campos, digitos) =>
  campos.some(campo => soDigitos(campo).includes(digitos));

// Letras buscam em nome, e-mail e empresa; só número busca em telefone e
// documento (com ou sem pontuação).
export const combinaComBusca = (busca, { textos, numeros }) => {
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

// #3062 — os dois sentidos das ordens da aba Pessoas (lista/ordens.js), como
// o servidor ordena: sem acento nem maiúscula, e quem não tem o dado no fim nos
// dois sentidos.
const ausente = valor => valor === null || valor === undefined || valor === '';

const maisAntigoPrimeiro = campo => (a, b) => {
  const x = a[campo];
  const y = b[campo];
  if (ausente(x)) return ausente(y) ? 0 : 1;
  if (ausente(y)) return -1;
  return x - y;
};

const porTexto = (ler, sentido) => (a, b) => {
  const x = normalizado(ler(a));
  const y = normalizado(ler(b));
  if (!x) return y ? 1 : 0;
  if (!y) return -1;
  if (x === y) return 0;
  return (x < y ? -1 : 1) * sentido;
};

const CRESCENTE = 1;
const DECRESCENTE = -1;
const adicional = chave => pessoa => pessoa.additional_attributes?.[chave];

const ORDENADORES = {
  [ORDENS.ULTIMA_CONVERSA]: maisRecentePrimeiro('last_activity_at'),
  [ORDENS.NOME]: porNome,
  [ORDENS.MAIS_NOVOS]: maisRecentePrimeiro('created_at'),
  conversa_mais_antiga: maisAntigoPrimeiro('last_activity_at'),
  nome_z_a: porTexto(pessoa => pessoa.name, DECRESCENTE),
  email_a_z: porTexto(pessoa => pessoa.email, CRESCENTE),
  email_z_a: porTexto(pessoa => pessoa.email, DECRESCENTE),
  empresa_a_z: porTexto(adicional('company_name'), CRESCENTE),
  empresa_z_a: porTexto(adicional('company_name'), DECRESCENTE),
  cidade_a_z: porTexto(adicional('city'), CRESCENTE),
  cidade_z_a: porTexto(adicional('city'), DECRESCENTE),
  pais_a_z: porTexto(adicional('country'), CRESCENTE),
  pais_z_a: porTexto(adicional('country'), DECRESCENTE),
  mais_antigos: maisAntigoPrimeiro('created_at'),
  // #3078 — as da aba Empresas (lista/ordens.js), como o servidor ordena.
  site_a_z: porTexto(empresa => empresa.domain, CRESCENTE),
  site_z_a: porTexto(empresa => empresa.domain, DECRESCENTE),
  mais_pessoas: (a, b) => b.contacts_count - a.contacts_count,
  menos_pessoas: (a, b) => a.contacts_count - b.contacts_count,
};

// ---- demonstração ----------------------------------------------------------

const REGRAS_DA_ABA = {
  [ABAS.PESSOAS]: {
    daBase: (base, agora) => base.pessoas(agora),
    pertence: pertenceAoGrupo,
    campos: camposDaPessoa,
    passaNosFiltros: pessoaPassaNosFiltros,
  },
  [ABAS.EMPRESAS]: {
    daBase: (base, agora) => base.empresas(agora),
    pertence: empresaPertenceAoGrupo,
    campos: camposDaEmpresa,
    passaNosFiltros: empresaPassaNosFiltros,
  },
};

const regrasDaAba = aba => REGRAS_DA_ABA[aba] || REGRAS_DA_ABA[ABAS.PESSOAS];

// O que a busca e os filtros deixam passar, antes de olhar o grupo. A lista e as
// contagens das pílulas usam esta mesma conta, para os números baterem.
const passaNaConsulta =
  (aba, { busca = '', filtros = {} }, agora, regras) =>
  item =>
    combinaComBusca(busca, regras.campos(item)) &&
    regras.passaNosFiltros(item, filtros, agora);

// #2897 — as regras da aba Pessoas com o que a carteira de seguros soma: os
// grupos dela (`extra.grupos`: id -> quem pertence) e mais lugares onde a busca
// procura (`extra.campos`). Em Empresas nada muda.
const comACarteira = (regras, aba, extra) =>
  aba === ABAS.EMPRESAS
    ? regras
    : {
        ...regras,
        pertence: (item, grupoId, agora) =>
          grupoId in extra.grupos
            ? extra.grupos[grupoId](item)
            : regras.pertence(item, grupoId, agora),
        campos: item => {
          const daLista = regras.campos(item);
          const dosSeguros = extra.campos(item);
          return {
            textos: [...daLista.textos, ...dosSeguros.textos],
            numeros: [...daLista.numeros, ...dosSeguros.numeros],
          };
        },
      };

// `comSeguros()`: a conta tem a carteira de seguros, perguntado a cada leitura.
// `carteira`: o que a carteira fictícia soma à lista de pessoas (uma função do
// agora), ou nulo quando a demonstração não tem a carteira fictícia.
const fonteDemo = ({ estado, carregarDemo, atraso, carteira, comSeguros }) => {
  const baseDaDemo = async () => {
    // `?demo=carregando`: a fonte nunca responde, para o print do esqueleto.
    if (estado === DEMO_CARREGANDO) return esperarParaSempre();
    await esperar(atraso);
    return estado === 'vazio' ? BASE_VAZIA : carregarDemo();
  };
  const contarGrupo = (lista, regras, grupoId, agora) =>
    lista.filter(item => regras.pertence(item, grupoId, agora)).length;
  const regrasDe = async (aba, agora) =>
    carteira && comSeguros()
      ? comACarteira(regrasDaAba(aba), aba, await carteira(agora))
      : regrasDaAba(aba);

  const achar = async ({
    aba = ABAS.PESSOAS,
    grupo = GRUPO_PADRAO[aba],
    busca = '',
    ordem = ORDENS.ULTIMA_CONVERSA,
    filtros = {},
  }) => {
    const agora = Date.now();
    const base = await baseDaDemo();
    const regras = await regrasDe(aba, agora);
    const ordenador = ORDENADORES[ordem] || ORDENADORES[ORDENS.ULTIMA_CONVERSA];
    return regras
      .daBase(base, agora)
      .filter(item => regras.pertence(item, grupo || GRUPO_PADRAO[aba], agora))
      .filter(passaNaConsulta(aba, { busca, filtros }, agora, regras))
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
      const base = await baseDaDemo();
      const regras = await regrasDe(aba, agora);
      const lista = regras
        .daBase(base, agora)
        .filter(passaNaConsulta(aba, consulta, agora, regras));
      return Object.fromEntries(
        gruposDaAba(aba, { comSeguros: comSeguros() }).map(grupo => [
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
      const daBase = base.empresas(Date.now());
      return {
        cidades_das_empresas: unicos(daBase.map(e => e.city)).map(comoOpcao),
        empresas: daBase
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
  // #3097 — os filtros de compra.
  compras: 'compras',
  totalAcima: 'total_acima',
};

const filtrosDoPedido = (filtros = {}) =>
  Object.entries(FILTRO_NO_SERVIDOR).map(([daTela, noServidor]) => [
    `filtros[${noServidor}]`,
    filtros[daTela],
  ]);

// #3078 — em Empresas vão só a cidade e o período de chegada: o servidor
// responde 422 para os filtros que a empresa não tem.
const filtrosDaAba = (aba, filtros = {}) =>
  aba === ABAS.EMPRESAS
    ? Object.fromEntries(
        FILTROS_DAS_EMPRESAS.map(chave => [chave, filtros[chave]])
      )
    : filtros;

// #3168 — "Por outra informação" (só em Pessoas): as linhas prontas no formato
// do payload de `contacts/filter` (lista/informacoes.js), em JSON no parâmetro
// `condicoes` (no servidor, Relacionamentos::CondicoesDaLista). Sem linha
// pronta, o parâmetro não vai.
const condicoesDoPedido = (aba, filtros = {}) => {
  if (aba === ABAS.EMPRESAS) return '';
  const payload = paraOServidor(filtros.condicoes, filtros.juntar);
  return payload.length ? JSON.stringify(payload) : '';
};

// O que vai na URL: só o que está preenchido.
export const paramsDoPedido = ({ aba, grupo, busca, ordem, pagina, filtros }) =>
  Object.fromEntries(
    [
      ['grupo', grupo],
      ['busca', busca],
      ['ordem', ordem],
      ['pagina', pagina],
      ...filtrosDoPedido(filtrosDaAba(aba, filtros)),
      ['condicoes', condicoesDoPedido(aba, filtros)],
    ].filter(([, valor]) => preenchido(valor))
  );

// Toda leitura do servidor passa por `doServidor` (fonte/doServidor.js): a
// recusa por falta de acesso (401 quando a permissão de ver recusa, 403 quando
// Empresas está desligada na conta) ganha nome; o resto sobe como veio.
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

// `comSeguros`: a conta tem a carteira de seguros (o valor, ou o `computed` de
// useContaDeSeguros: é lido a cada leitura, porque a conta pode chegar depois
// de a tela montar). Só a demonstração usa: na fonte real o servidor já sabe,
// e o grupo e a busca vão no mesmo pedido. `?demo=sem-seguros` é a conta de
// seguros que ainda não tem nenhum.
export const listaFonte = ({
  demo = null,
  comSeguros = false,
  carregarDemo = CARREGAR_DEMO,
  carregarCarteira = CARREGAR_CARTEIRA,
  atraso = ATRASO_DA_DEMO_MS,
} = {}) => {
  if (!demo || !carregarDemo) return fonteReal();
  const temCarteiraFicticia = carregarCarteira && demo !== DEMO_SEM_SEGUROS;
  return fonteDemo({
    estado: demo,
    carregarDemo,
    atraso,
    comSeguros: () => Boolean(toValue(comSeguros)),
    carteira: temCarteiraFicticia
      ? async agora => (await carregarCarteira()).carteiraNaLista(agora)
      : null,
  });
};
