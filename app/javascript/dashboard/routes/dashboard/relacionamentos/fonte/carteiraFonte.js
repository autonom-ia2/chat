// #2897 — de onde a carteira de seguros lê e grava (molde: listaFonte.js e
// fichaFonte.js). A tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real: ainda não existe; todo método diz `FONTE_REAL_PENDENTE`;
//   2. demonstração: com `?demo=<estado>` e só no ambiente de desenvolvimento.
//      Os dados são inventados (demo/carteira.js), a escrita só fica na memória
//      e tudo demora um instante, como a rede.
// `peca` é o `?demo-carteira=`: muda só esta fonte (carregando, erro, vazio).
// `caso` é o `?caso=` (fonte/modoCarteira.js): um estado que o exemplo não mostra.
import {
  ABA_SEGUROS,
  GRUPO_PADRAO_DE_SEGUROS,
  gruposDeSeguros,
  seguroPertenceAoGrupo,
} from './gruposDeSeguros';
import {
  POR_PAGINA,
  combinaComBusca,
  erroFonteRealPendente,
  esperar,
} from './listaFonte';
import { DEMO_CARREGANDO, esperarParaSempre } from './modoDemo';
import { aggerLigadoNaDemo } from './modoCarteira';
import {
  SELOS,
  diasParaTerminar,
  estaValendo,
  maisUrgente,
  porUrgencia,
  seloDoSeguro,
} from './selosDoSeguro';

const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/carteira.js')
  : null;

export const ATRASO_DA_CARTEIRA_MS = 300;
const PRIMEIRA_PAGINA = 1;
const LOCALE_DA_ORDEM_ALFABETICA = 'pt-BR';

export const ORDENS_DE_SEGUROS = {
  VENCE_PRIMEIRO: 'vence_primeiro',
  NOME: 'nome',
  MAIS_NOVOS: 'mais_novos',
};

export const FILTROS_DE_SEGUROS_VAZIOS = Object.freeze({
  tipo: '',
  seguradora: '',
  cuida: '',
});

export const contarFiltrosDeSeguros = (filtros = {}) =>
  Object.keys(FILTROS_DE_SEGUROS_VAZIOS).filter(chave => filtros[chave]).length;

// ---- ordem, busca e filtros -------------------------------------------------

// Quem ainda vale vem antes, do que termina mais cedo ao mais tarde; depois os
// outros, do que terminou há menos tempo ao mais antigo.
const venceAntes = agora => (a, b) => {
  const valeA = estaValendo(a, agora);
  const valeB = estaValendo(b, agora);
  if (valeA !== valeB) return valeA ? -1 : 1;
  return valeA ? a.termina - b.termina : b.termina - a.termina;
};

const ordenador = (ordem, agora) =>
  ({
    [ORDENS_DE_SEGUROS.NOME]: (a, b) =>
      a.segurado.nome.localeCompare(
        b.segurado.nome,
        LOCALE_DA_ORDEM_ALFABETICA
      ),
    [ORDENS_DE_SEGUROS.MAIS_NOVOS]: (a, b) => b.comeca - a.comeca,
  })[ordem] ?? venceAntes(agora);

const camposDoSeguro = seguro => ({
  textos: [
    seguro.pessoa.name,
    seguro.segurado.nome,
    seguro.placa,
    seguro.numero,
  ],
  numeros: [seguro.numero, seguro.segurado.documento],
});

const passaNosFiltros = (seguro, { tipo, seguradora, cuida } = {}) =>
  (!tipo || seguro.tipo === tipo) &&
  (!seguradora || seguro.seguradora === seguradora) &&
  (!cuida || seguro.renovacao?.cuida === cuida);

const passaNaConsulta =
  ({ busca = '', filtros = {} } = {}) =>
  seguro =>
    combinaComBusca(busca, camposDoSeguro(seguro)) &&
    passaNosFiltros(seguro, filtros);

const unicos = lista => [...new Set(lista.filter(Boolean))].sort();

// ---- o que a lista de pessoas e de empresas usa -----------------------------

const resumoDeUmDono = (seguros, agora) => {
  const urgente = maisUrgente(seguros, agora);
  return {
    quantos: seguros.length,
    selo: urgente?.selo ?? null,
    tipo: urgente?.seguro.tipo ?? null,
    dias: urgente ? diasParaTerminar(urgente.seguro, agora) : null,
    desde: Math.min(...seguros.map(seguro => seguro.comeca)),
    busca: seguros
      .flatMap(seguro => [seguro.placa, seguro.numero])
      .filter(Boolean),
  };
};

const agruparPor = (lista, chaveDe) =>
  lista.reduce((grupos, item) => {
    const chave = chaveDe(item);
    if (chave === null || chave === undefined) return grupos;
    return { ...grupos, [chave]: [...(grupos[chave] ?? []), item] };
  }, {});

const resumoPorDono = (seguros, chaveDe, agora) =>
  Object.fromEntries(
    Object.entries(agruparPor(seguros, chaveDe)).map(([chave, deles]) => [
      chave,
      resumoDeUmDono(deles, agora),
    ])
  );

const empresaSegurada = seguro =>
  seguro.segurado.tipo === 'empresa' ? seguro.segurado.id : null;

// ---- demonstração -----------------------------------------------------------

const ESTADOS_SEM_SEGURO = ['vazio', 'sem-seguros', 'fora-do-segmento'];
const ESCRITAS = [
  'corrigir',
  'cancelar',
  'voltarAAtivo',
  'guardarPdf',
  'desfazerPdf',
  'cotar',
  'lerPdf',
];

// O seguro que a pessoa tem em outra corretora (Tela 20): os arquivos que
// vieram na conversa, a leitura de um deles, guardar o lembrete e desfazer.
const ESCRITAS_DE_FORA = ['lerDeFora', 'guardarDeFora', 'desfazerDeFora'];
const DE_FORA = ['arquivosDaConversa', ...ESCRITAS_DE_FORA];

const erroDaDemo = () =>
  Object.assign(new Error('A demonstração pediu o erro desta peça.'), {
    name: 'ERRO_DA_DEMO',
  });

const naoAchei = () =>
  Object.assign(new Error('Este seguro não está mais aqui.'), {
    name: 'NAO_ACHEI',
  });

const fonteDemo = ({ estado, peca, caso, carregarDemo, atraso }) => {
  const semSeguro = ESTADOS_SEM_SEGURO.includes(estado) || peca === 'vazio';
  const aggerLigado = aggerLigadoNaDemo(estado);

  const demo = async () => {
    if (estado === DEMO_CARREGANDO || peca === 'carregando') {
      return esperarParaSempre();
    }
    await esperar(atraso);
    if (peca === 'erro') throw erroDaDemo();
    return (await carregarDemo()).demoDaCarteira;
  };
  const daCarteira = async agora =>
    semSeguro ? (await demo(), []) : (await demo()).segurosDaCarteira(agora);
  const comOsDeFora = async agora =>
    semSeguro ? (await demo(), []) : (await demo()).segurosComOsDeFora(agora);

  const achar = async ({
    grupo = GRUPO_PADRAO_DE_SEGUROS,
    busca = '',
    ordem = ORDENS_DE_SEGUROS.VENCE_PRIMEIRO,
    filtros = {},
  } = {}) => {
    const agora = Date.now();
    return (await daCarteira(agora))
      .filter(seguro =>
        seguroPertenceAoGrupo(seguro, grupo || GRUPO_PADRAO_DE_SEGUROS, agora)
      )
      .filter(passaNaConsulta({ busca, filtros }))
      .sort(ordenador(ordem, agora));
  };

  const escrita =
    nome =>
    async (id, ...resto) => {
      const dados = await demo();
      if (semSeguro || !dados.seguroPorId(id)) throw naoAchei();
      return dados[nome](id, ...resto);
    };

  return {
    usaDemo: true,
    // Cota sozinha quem tem o Agger ligado (na entrega real, também a chave da
    // cotação de renovação).
    cotaSozinha: aggerLigado,
    async resumo() {
      const agora = Date.now();
      const seguros = await daCarteira(agora);
      const em7 = seguros.filter(s =>
        seguroPertenceAoGrupo(s, 'vence_7_dias', agora)
      );
      const emRenovacao = s => seloDoSeguro(s, agora) === SELOS.EM_RENOVACAO;
      return {
        total: seguros.length,
        vence7: em7.length,
        vence7EmRenovacao: em7.filter(emRenovacao).length,
        emRenovacao: seguros.filter(emRenovacao).length,
        aggerLigado,
      };
    },
    // Aceita `(consulta)` e também `(aba, consulta)`, como a lista do bloco A.
    async contagens(...argumentos) {
      const consulta = argumentos.find(item => typeof item === 'object') ?? {};
      const agora = Date.now();
      const lista = (await daCarteira(agora)).filter(passaNaConsulta(consulta));
      return Object.fromEntries(
        gruposDeSeguros({ aggerLigado }).map(({ id }) => [
          id,
          lista.filter(seguro => seguroPertenceAoGrupo(seguro, id, agora))
            .length,
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
    async listarTodos(pedido = {}) {
      const achados = await achar(pedido);
      return { itens: achados, total: achados.length };
    },
    async opcoesDeFiltro() {
      const seguros = await daCarteira(Date.now());
      return {
        tipos: unicos(seguros.map(s => s.tipo)),
        seguradoras: unicos(seguros.map(s => s.seguradora)),
        cuida: unicos(seguros.map(s => s.renovacao?.cuida)),
      };
    },
    async daPessoa(id) {
      const agora = Date.now();
      const dela = (await comOsDeFora(agora)).filter(s => s.pessoaId === id);
      return porUrgencia(dela, agora);
    },
    async daEmpresa(id) {
      const agora = Date.now();
      const dela = (await daCarteira(agora)).filter(
        s => empresaSegurada(s) === id
      );
      return porUrgencia(dela, agora);
    },
    async seguro(id) {
      const dados = await demo();
      return semSeguro ? null : dados.seguroPorId(id);
    },
    async historia(id) {
      const dados = await demo();
      return semSeguro ? [] : dados.historiaDoSeguro(id);
    },
    async resumoPorPessoa() {
      const agora = Date.now();
      return resumoPorDono(await daCarteira(agora), s => s.pessoaId, agora);
    },
    async resumoPorEmpresa() {
      const agora = Date.now();
      return resumoPorDono(await daCarteira(agora), empresaSegurada, agora);
    },
    ...Object.fromEntries(ESCRITAS.map(nome => [nome, escrita(nome)])),
    // `?caso=` mostra a gaveta carregando, com erro ou sem arquivo na conversa.
    async arquivosDaConversa(pessoaId) {
      if (caso === 'de_fora_carregando') return esperarParaSempre();
      const dados = await demo();
      if (caso === 'de_fora_erro') throw erroDaDemo();
      const conversa = dados.arquivosDaConversa(pessoaId);
      return caso === 'de_fora_sem_arquivos'
        ? { ...conversa, arquivos: [] }
        : conversa;
    },
    ...Object.fromEntries(
      ESCRITAS_DE_FORA.map(nome => [
        nome,
        async (...dados) => (await demo())[nome](...dados),
      ])
    ),
  };
};

// ---- fonte real (pendente) --------------------------------------------------

const LEITURAS = [
  'resumo',
  'contagens',
  'listar',
  'listarTodos',
  'opcoesDeFiltro',
  'daPessoa',
  'daEmpresa',
  'seguro',
  'historia',
  'resumoPorPessoa',
  'resumoPorEmpresa',
];

const fonteReal = () => {
  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  return {
    usaDemo: false,
    cotaSozinha: false,
    ...Object.fromEntries(
      [...LEITURAS, ...ESCRITAS, ...DE_FORA].map(nome => [nome, pendente])
    ),
  };
};

export const carteiraFonte = ({
  demo = null,
  peca = null,
  caso = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_CARTEIRA_MS,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({ estado: demo, peca, caso, carregarDemo, atraso })
    : fonteReal();

export { ABA_SEGUROS };
