// #2894 — de onde a ficha de Relacionamentos lê e grava (molde: listaFonte.js). A
// tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real: ainda não existe; todo método diz `FONTE_REAL_PENDENTE`;
//   2. demonstração: com `?demo=<estado>` (modoDemo.js) e só no ambiente de
//      desenvolvimento. Os dados são inventados (demo/ficha.js), a escrita só
//      fica na memória e tudo demora um instante, como a rede.
// O `import.meta.env.DEV` vira `false` no build de produção: o ramo some e os
// dados fictícios nem entram no pacote.
import { erroFonteRealPendente } from './listaFonte';
import { demoCarregando, esperarParaSempre } from './modoDemo';

const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/ficha.js')
  : null;

export const ATRASO_DA_FICHA_MS = 300;

// O que cada método devolve quando a conta está vazia (?demo=vazio): ninguém
// existe, então toda leitura volta sem nada e toda escrita diz "não achei".
const LEITURAS = {
  pessoa: null,
  conversas: [],
  cards: [],
  notas: [],
  arquivos: [],
  origem: null,
  empresa: null,
  pessoasDaEmpresa: [],
  conversasDaEmpresa: [],
  cardsDaEmpresa: [],
};
const ESCRITAS = [
  'salvar',
  'salvarEmpresa',
  'marcarCliente',
  'guardarNota',
  'liberarMensagens',
];
const METODOS = [...Object.keys(LEITURAS), ...ESCRITAS];

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const naoAchei = () =>
  Object.assign(new Error('Não achei esta pessoa.'), { name: 'NAO_ACHEI' });

// As leituras que abrem a ficha: em `?demo=carregando` nenhuma resposta chega.
const LEITURAS_DA_FICHA = ['pessoa', 'empresa'];

const fonteDemo = ({ estado, carregarDemo, atraso }) => {
  const metodo =
    nome =>
    async (...argumentos) => {
      if (LEITURAS_DA_FICHA.includes(nome) && demoCarregando()) {
        return esperarParaSempre();
      }
      await esperar(atraso);
      if (estado === 'vazio') {
        if (nome in LEITURAS) return LEITURAS[nome];
        throw naoAchei();
      }
      const { demoDaFicha } = await carregarDemo();
      return demoDaFicha[nome](...argumentos);
    };
  return {
    usaDemo: true,
    ...Object.fromEntries(METODOS.map(nome => [nome, metodo(nome)])),
  };
};

const fonteReal = () => {
  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  return {
    usaDemo: false,
    ...Object.fromEntries(METODOS.map(nome => [nome, pendente])),
  };
};

export const fichaFonte = ({
  demo = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_FICHA_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, carregarDemo, atraso })
    : fonteReal();
