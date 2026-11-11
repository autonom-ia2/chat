// #2897 — de onde "trazer seguros" lê e para onde escreve (molde:
// fonte/trazerFonte.js). A tela recebe sempre o mesmo formato:
//   1. fonte real: ainda não existe; todo método diz `FONTE_REAL_PENDENTE`;
//   2. demonstração: com `?demo=<estado>` e só no desenvolvimento. Nada é lido
//      de verdade: a planilha, os PDFs e o Agger devolvem a leitura fictícia de
//      demo/trazerSeguros.js, e o que foi trazido fica na memória do módulo.
// A planilha é a mesma do bloco A: `listas` é a fonte dele (fonte/trazerFonte.js),
// que lê as pessoas e guarda as listas; aqui os seguros entram por cima, e o
// histórico mostra os dois juntos.
// `peca` é o `?demo-carteira=` (carregando, erro) e `caso` o `?caso=`, que faz a
// demonstração cair num estado que o exemplo não mostra (fonte/modoCarteira.js).
import {
  pessoasDosSeguros,
  totalDeSeguros,
} from '../carteira/contagemDeSeguros';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';
import {
  ATRASO_DA_DEMO_MS,
  erroFonteRealPendente,
  esperar,
} from './listaFonte';
import { aggerLigadoNaDemo } from './modoCarteira';
import { DEMO_CARREGANDO, esperarParaSempre } from './modoDemo';

const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/trazerSeguros.js')
  : null;

// Na demonstração qualquer login entra, menos quando a pessoa escreve esta
// palavra no lugar da senha (é só um gatilho do exemplo, não é credencial).
export const NAO_ENTRA_NA_DEMO = 'errada';

const copia = valor => JSON.parse(JSON.stringify(valor));

const erroNomeado = (nome, mensagem) =>
  Object.assign(new Error(mensagem), { name: nome });

// ---- memória do módulo --------------------------------------------------------

let memoria = null;

export const esquecerTrazerSeguros = () => {
  memoria = null;
};

const memoriaDa = (estado, demo, agora) => {
  if (memoria?.estado !== estado) {
    memoria = {
      estado,
      contador: 0,
      aggerLigado: aggerLigadoNaDemo(estado),
      leituras: new Map(),
      pdfs: new Map(),
      buscas: new Map(),
      entradas: demo.historicoDeSeguros(agora, estado),
      // Casos que falham uma vez só: depois de gastos, a nova tentativa passa.
      gastos: new Set(),
    };
  }
  return memoria;
};

const proximoId = (prefixo, mem) => {
  mem.contador += 1;
  return `${prefixo}-${mem.contador}`;
};

// ---- o que a tela vê de cada entrada do histórico -----------------------------

const vistaDaEntrada = (entrada, agora, demo) => {
  const trazendo = entrada.situacao === SITUACOES_DA_LISTA.TRAZENDO;
  const porcentagem = trazendo
    ? demo.porcentagemDaTrazida(entrada.quando, agora)
    : 100;
  const terminou = trazendo && porcentagem >= 100;
  return {
    ...entrada,
    situacao: terminou ? SITUACOES_DA_LISTA.PRONTO : entrada.situacao,
    porcentagem,
  };
};

// ---- demonstração -------------------------------------------------------------

const fonteDemo = ({
  estado,
  peca,
  caso,
  listas,
  carregarDemo,
  atraso,
  agora,
}) => {
  const carregar = async () => (await carregarDemo()).demoDeTrazerSeguros;
  const dados = async () => {
    if (estado === DEMO_CARREGANDO || peca === 'carregando') {
      return esperarParaSempre();
    }
    await esperar(atraso);
    if (peca === 'erro') {
      throw erroNomeado('ERRO_DA_DEMO', 'A demonstração pediu o erro.');
    }
    const demo = await carregar();
    return { demo, mem: memoriaDa(estado, demo, agora()) };
  };
  // O caso pedido falha uma vez; a tentativa seguinte passa.
  const falhaAgora = (mem, nome) => {
    if (caso !== nome || mem.gastos.has(nome)) return false;
    mem.gastos.add(nome);
    return true;
  };
  const acharEm = (mapa, id, nome) => {
    if (!mapa.has(id)) throw erroNomeado(nome, 'Não achei.');
    return mapa.get(id);
  };
  const entradaDe = (mem, id) => mem.entradas.find(item => item.id === id);
  const trocarEntrada = (mem, id, mudanca) => {
    mem.entradas = mem.entradas.map(item =>
      item.id === id ? { ...item, ...mudanca } : item
    );
  };
  const escrever = async (leituraId, mudar) => {
    const { demo, mem } = await dados();
    const atual = acharEm(mem.leituras, leituraId, 'LEITURA_NAO_ENCONTRADA');
    const nova = mudar(demo, atual);
    mem.leituras.set(leituraId, nova);
    return copia(nova);
  };
  const comecarBusca = mem => {
    const buscaId = proximoId('busca', mem);
    mem.buscas.set(buscaId, { inicio: agora(), denovoDesde: null });
    return { buscaId };
  };
  // A busca como está agora; quando termina, a leitura do que o Agger achou.
  const vistaDaBusca = (demo, mem, buscaId) => {
    const busca = acharEm(mem.buscas, buscaId, 'BUSCA_NAO_ENCONTRADA');
    const { seguradoras, terminou } = demo.buscaDoAgger(
      busca.inicio,
      agora(),
      busca.denovoDesde
    );
    if (terminou && !mem.leituras.has(buscaId)) {
      mem.leituras.set(buscaId, demo.leituraDoAgger(buscaId, agora()));
    }
    return {
      seguradoras,
      leitura: terminou ? copia(mem.leituras.get(buscaId)) : null,
    };
  };

  return {
    usaDemo: true,
    planilhaDeDemo: listas.planilhaDeDemo,
    arquivoDeExemplo: () => listas.arquivoDeExemplo?.() ?? null,
    pdfsDeExemplo: async () => (await carregar()).pdfsDeExemplo(),

    // `renovacoes`: se a conta já escolheu onde ficam as renovações (senão a
    // pergunta aparece antes de conferir), os funis dela e se quem está usando
    // pode mexer neles.
    async comeco() {
      const { demo, mem } = await dados();
      return {
        aggerLigado: mem.aggerLigado,
        renovacoes: {
          ...demo.renovacoesNaDemo(estado),
          semPermissao: caso === 'sem_permissao_de_funil',
        },
      };
    },
    // `escolha` nula = seguir sem escolher (quem não pode mexer em funis).
    escolherRenovacoes: (leituraId, escolha) =>
      escrever(leituraId, (demo, leitura) =>
        demo.escolherRenovacoes(leitura, escolha, agora())
      ),

    // ---- planilha
    async lerPlanilha(arquivo) {
      const exemplo = { name: (await carregar()).PLANILHA_DE_EXEMPLO };
      const pessoas = await listas.ler(arquivo ?? exemplo);
      const { demo, mem } = await dados();
      const id = proximoId('seguros', mem);
      const leitura = {
        ...demo.leituraDaPlanilha(id, pessoas.arquivo, agora()),
        pessoas,
      };
      mem.leituras.set(id, leitura);
      return copia(leitura);
    },

    // ---- PDFs
    async lerPdfs(arquivos) {
      const { mem } = await dados();
      const leituraId = proximoId('pdfs', mem);
      mem.pdfs.set(leituraId, { inicio: agora(), total: arquivos.length });
      return { leituraId };
    },
    async andamentoDosPdfs(leituraId) {
      const { demo, mem } = await dados();
      const lote = acharEm(mem.pdfs, leituraId, 'LEITURA_NAO_ENCONTRADA');
      if (falhaAgora(mem, 'pdfs_nao_leu')) {
        throw erroNomeado('NAO_LEU', 'Não consegui ler os PDFs.');
      }
      const lidos = demo.pdfsLidos(lote.inicio, agora(), lote.total);
      if (lidos < lote.total) {
        return { lidos, total: lote.total, leitura: null };
      }
      if (!mem.leituras.has(leituraId)) {
        mem.leituras.set(
          leituraId,
          demo.leituraDosPdfs(leituraId, agora(), caso)
        );
      }
      return {
        lidos,
        total: lote.total,
        leitura: copia(mem.leituras.get(leituraId)),
      };
    },

    // ---- Agger
    async entrarNoAgger({ senha }) {
      const { mem } = await dados();
      if (senha === NAO_ENTRA_NA_DEMO) {
        throw erroNomeado(
          'LOGIN_NAO_CONFERE',
          'Usuário ou senha não conferem.'
        );
      }
      if (caso === 'agger_sem_apolices') {
        throw erroNomeado('AGGER_SEM_APOLICES', 'Sem a parte de apólices.');
      }
      mem.aggerLigado = true;
      return comecarBusca(mem);
    },
    async buscarNoAgger() {
      const { mem } = await dados();
      if (!mem.aggerLigado) {
        throw erroNomeado('AGGER_NAO_LIGADO', 'A conta não está ligada.');
      }
      return comecarBusca(mem);
    },
    async andamentoDaBusca(buscaId) {
      const { demo, mem } = await dados();
      const vista = vistaDaBusca(demo, mem, buscaId);
      const algumaChegou = vista.seguradoras.some(s => s.situacao === 'pronta');
      if (algumaChegou && falhaAgora(mem, 'agger_nao_respondeu')) {
        throw erroNomeado('AGGER_NAO_RESPONDEU', 'O Agger não respondeu.');
      }
      return vista;
    },
    async buscarDeNovo(buscaId) {
      const { demo, mem } = await dados();
      const busca = acharEm(mem.buscas, buscaId, 'BUSCA_NAO_ENCONTRADA');
      mem.buscas.set(buscaId, { ...busca, denovoDesde: agora() });
      return vistaDaBusca(demo, mem, buscaId);
    },

    // ---- conferir
    consertar: (leituraId, linha, valor) =>
      escrever(leituraId, (demo, leitura) =>
        demo.aplicarConserto(leitura, linha, valor)
      ),
    deixarDeFora: (leituraId, linha) =>
      escrever(leituraId, (demo, leitura) =>
        demo.aplicarDeixarDeFora(leitura, linha)
      ),
    reabrir: (leituraId, linha) =>
      escrever(leituraId, (demo, leitura) =>
        demo.aplicarReabrir(leitura, linha)
      ),
    trocarDestino: (leituraId, coluna, destino) =>
      escrever(leituraId, (demo, leitura) =>
        demo.aplicarDestino(leitura, coluna, destino)
      ),

    // ---- trazer
    async trazer(leituraId) {
      const { demo, mem } = await dados();
      const leitura = acharEm(
        mem.leituras,
        leituraId,
        'LEITURA_NAO_ENCONTRADA'
      );
      if (falhaAgora(mem, 'trazer_falhou')) {
        throw erroNomeado('NAO_TROUXE', 'Não consegui trazer os seguros.');
      }
      const trazidaId = proximoId('seguros-trazidos', mem);
      const quantos = {
        seguros: totalDeSeguros(leitura),
        pessoas: pessoasDosSeguros(leitura),
      };
      mem.entradas = [
        demo.entradaTrazida(trazidaId, leitura, quantos, agora()),
        ...mem.entradas,
      ];
      return { trazidaId };
    },
    async andamento(trazidaId) {
      const { demo, mem } = await dados();
      const entrada = entradaDe(mem, trazidaId);
      if (!entrada) throw erroNomeado('LISTA_NAO_ENCONTRADA', 'Não achei.');
      const vista = vistaDaEntrada(entrada, agora(), demo);
      return {
        porcentagem: vista.porcentagem,
        situacao: vista.situacao,
        seguros: entrada.seguros,
        pessoas: entrada.pessoas,
      };
    },

    // ---- o que a conta já trouxe: os seguros e, depois, as listas do bloco A
    async historico() {
      const { demo, mem } = await dados();
      const deListas = await listas.historico();
      const momento = agora();
      return [
        ...mem.entradas.map(item => vistaDaEntrada(item, momento, demo)),
        ...deListas,
      ];
    },
    async previaDoDesfazer(id) {
      const { mem } = await dados();
      const entrada = entradaDe(mem, id);
      if (!entrada) return listas.previaDoDesfazer(id);
      const { tipo, seguros, pessoas, cards, propostas } = entrada;
      return { origem: tipo, seguros, pessoas, cards, propostas };
    },
    async desfazer(id) {
      const { demo, mem } = await dados();
      const entrada = entradaDe(mem, id);
      if (!entrada) return listas.desfazer(id);
      const { situacao } = vistaDaEntrada(entrada, agora(), demo);
      if (situacao !== SITUACOES_DA_LISTA.PRONTO) {
        throw erroNomeado('NAO_PODE_DESFAZER', 'Não dá para desfazer agora.');
      }
      trocarEntrada(mem, id, { situacao: SITUACOES_DA_LISTA.DESFEITO });
      return { id, situacao: SITUACOES_DA_LISTA.DESFEITO };
    },
    // "Parar de buscar todo dia" (o que já veio do Agger fica) e o caminho de
    // volta, sem prazo.
    async buscarTodoDia(id, ligado) {
      const { demo, mem } = await dados();
      if (!entradaDe(mem, id)) {
        throw erroNomeado('LISTA_NAO_ENCONTRADA', 'Não achei.');
      }
      trocarEntrada(mem, id, { buscaTodoDia: ligado });
      return vistaDaEntrada(entradaDe(mem, id), agora(), demo);
    },
  };
};

// ---- fonte real (pendente) ------------------------------------------------------

const METODOS = [
  'pdfsDeExemplo',
  'comeco',
  'escolherRenovacoes',
  'lerPlanilha',
  'lerPdfs',
  'andamentoDosPdfs',
  'entrarNoAgger',
  'buscarNoAgger',
  'andamentoDaBusca',
  'buscarDeNovo',
  'consertar',
  'deixarDeFora',
  'reabrir',
  'trocarDestino',
  'trazer',
  'andamento',
  'historico',
  'previaDoDesfazer',
  'desfazer',
  'buscarTodoDia',
];

const fonteReal = () => {
  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  return {
    usaDemo: false,
    arquivoDeExemplo: () => null,
    ...Object.fromEntries(METODOS.map(nome => [nome, pendente])),
  };
};

export const trazerSegurosFonte = ({
  demo = null,
  peca = null,
  caso = null,
  listas = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
  agora = Date.now,
} = {}) =>
  demo && carregarDemo && listas
    ? fonteDemo({
        estado: demo,
        peca,
        caso,
        listas,
        carregarDemo,
        atraso,
        agora,
      })
    : fonteReal();
