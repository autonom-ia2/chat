import {
  ABAS,
  GRUPO_PADRAO,
  empresaPertenceAoGrupo,
  gruposDaAba,
  pertenceAoGrupo,
} from './grupos';
import { normalizado, soDigitos } from './texto';

// #2894 — de onde a lista de Relacionamentos lê (molde:
// autonomia/prospecting/achar/utils/acharFonte.js). A tela recebe sempre o mesmo
// formato, venha de onde vier:
//   1. fonte real: ainda não existe; entra na entrega de construção. Por ora
//      todo método diz `FONTE_REAL_PENDENTE`;
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

const esperar = ms =>
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

const fonteDemo = ({ estado, carregarDemo, atraso }) => {
  const baseDaDemo = async () => {
    await esperar(atraso);
    return estado === 'vazio' ? BASE_VAZIA : carregarDemo();
  };
  const contarGrupo = (lista, regras, grupoId, agora) =>
    lista.filter(item => regras.pertence(item, grupoId, agora)).length;

  return {
    usaDemo: true,
    async resumo() {
      const agora = Date.now();
      const gente = (await baseDaDemo()).pessoas(agora);
      const regras = REGRAS_DA_ABA[ABAS.PESSOAS];
      return {
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
    async contagens(aba) {
      const agora = Date.now();
      const regras = regrasDaAba(aba);
      const lista = regras.daBase(await baseDaDemo(), agora);
      return Object.fromEntries(
        gruposDaAba(aba).map(grupo => [
          grupo.id,
          contarGrupo(lista, regras, grupo.id, agora),
        ])
      );
    },
    async listar({
      aba = ABAS.PESSOAS,
      grupo = GRUPO_PADRAO[aba],
      busca = '',
      ordem = ORDENS.ULTIMA_CONVERSA,
      pagina = PRIMEIRA_PAGINA,
    } = {}) {
      const agora = Date.now();
      const regras = regrasDaAba(aba);
      const ordenador =
        ORDENADORES[ordem] || ORDENADORES[ORDENS.ULTIMA_CONVERSA];
      const achados = regras
        .daBase(await baseDaDemo(), agora)
        .filter(item =>
          regras.pertence(item, grupo || GRUPO_PADRAO[aba], agora)
        )
        .filter(item => combinaComBusca(busca, regras.campos(item)))
        .sort(ordenador);
      const inicio = (pagina - PRIMEIRA_PAGINA) * POR_PAGINA;
      return {
        itens: achados.slice(inicio, inicio + POR_PAGINA),
        total: achados.length,
        temMais: inicio + POR_PAGINA < achados.length,
      };
    },
  };
};

// ---- fonte real (pendente) -------------------------------------------------

const fonteReal = () => {
  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  return {
    usaDemo: false,
    resumo: pendente,
    contagens: pendente,
    listar: pendente,
  };
};

export const listaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, carregarDemo, atraso })
    : fonteReal();
