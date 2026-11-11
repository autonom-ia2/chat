import { ATRASO_DA_DEMO_MS, erroFonteRealPendente } from './listaFonte';
import { demoCarregando, esperarParaSempre } from './modoDemo';
import { resumoAoVivo, totalDaLeitura } from '../trazer/contagem';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

// #2894 — de onde "Trazer minha lista" lê e para onde escreve (molde:
// fonte/listaFonte.js). A tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real: ainda não existe; todo método diz `FONTE_REAL_PENDENTE`;
//   2. demonstração: com `?demo=<estado>` e só no desenvolvimento. O protótipo
//      NÃO lê o arquivo no navegador: qualquer planilha devolve a leitura
//      fictícia de demo/trazer.js. As escritas só ficam na memória do módulo
//      (a lista trazida continua lá quando a pessoa sai e volta) e cada método
//      devolve cópias novas.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/trazer.js')
  : null;

export const ATRASO_DA_LEITURA_MS = 1200;

// `?planilha=` (só em demonstração): faz a leitura cair num estado que a
// planilha de exemplo não mostra, sem precisar de arquivo de verdade.
export const PLANILHAS_DE_DEMO = [
  'nao_e_planilha',
  'vazia',
  'sem_contato',
  'lendo',
];
const ARQUIVOS_DE_MENTIRA = {
  nao_e_planilha: { name: 'foto.png' },
  vazia: { name: 'Planilha vazia.xlsx' },
  sem_contato: { name: 'Sem contato.xlsx' },
};

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

const copia = valor => JSON.parse(JSON.stringify(valor));

const erroNomeado = (nome, mensagem) =>
  Object.assign(new Error(mensagem), { name: nome });

// ---- memória do módulo -----------------------------------------------------

let memoria = null;

export const esquecerMemoriaDaDemo = () => {
  memoria = null;
};

const memoriaDa = (estado, demo, agora) => {
  if (memoria?.estado !== estado) {
    memoria = {
      estado,
      contador: 0,
      leituras: new Map(),
      listas: demo.historicoInicial(agora, estado),
    };
  }
  return memoria;
};

const proximoId = (prefixo, dados) => {
  dados.contador += 1;
  return `${prefixo}-${dados.contador}`;
};

// ---- a lista na conta: andamento e situação --------------------------------

const situacaoDaLista = (lista, agora, demo) => {
  if (lista.situacao !== SITUACOES_DA_LISTA.TRAZENDO) return lista.situacao;
  const porcentagem = demo.porcentagemDaTrazida(lista.quando, agora);
  return porcentagem >= 100 ? SITUACOES_DA_LISTA.PRONTO : lista.situacao;
};

const vistaDaLista = (lista, agora, demo) => {
  const situacao = situacaoDaLista(lista, agora, demo);
  return {
    id: lista.id,
    arquivo: lista.arquivo,
    quando: lista.quando,
    quem: lista.quem,
    total: lista.total,
    situacao,
    porcentagem:
      situacao === SITUACOES_DA_LISTA.TRAZENDO
        ? demo.porcentagemDaTrazida(lista.quando, agora)
        : 100,
  };
};

// ---- demonstração ----------------------------------------------------------

const fonteDemo = ({
  estado,
  planilha,
  carregarDemo,
  atraso,
  atrasoDaLeitura,
  agora,
}) => {
  const dados = async () => {
    const demo = await carregarDemo();
    return { demo, memoria: memoriaDa(estado, demo, agora()) };
  };
  const leituraDe = (dadosDaDemo, leituraId) => {
    const leitura = dadosDaDemo.memoria.leituras.get(leituraId);
    if (!leitura) {
      throw erroNomeado('LEITURA_NAO_ENCONTRADA', 'Essa leitura não existe.');
    }
    return leitura;
  };
  const listaDe = (dadosDaDemo, trazidaId) => {
    const lista = dadosDaDemo.memoria.listas.find(
      item => item.id === trazidaId
    );
    if (!lista) {
      throw erroNomeado('LISTA_NAO_ENCONTRADA', 'Essa lista não existe.');
    }
    return lista;
  };
  // Escrita na leitura: espera um pouco, troca a leitura por uma nova e devolve cópia.
  const escrever = async (leituraId, mudar) => {
    await esperar(atraso);
    const dadosDaDemo = await dados();
    const nova = mudar(dadosDaDemo.demo, leituraDe(dadosDaDemo, leituraId));
    dadosDaDemo.memoria.leituras.set(leituraId, nova);
    return copia(nova);
  };

  return {
    usaDemo: true,
    planilhaDeDemo: planilha,
    arquivoDeExemplo: () => ARQUIVOS_DE_MENTIRA[planilha] ?? null,
    async ler(arquivo) {
      // `?planilha=lendo`: a leitura nunca termina, para o print do "lendo".
      if (planilha === 'lendo') return esperarParaSempre();
      await esperar(atrasoDaLeitura);
      if (planilha === 'vazia') {
        throw erroNomeado('PLANILHA_VAZIA', 'A planilha está vazia.');
      }
      if (planilha === 'sem_contato') {
        throw erroNomeado('PLANILHA_SEM_CONTATO', 'Não achei nome e contato.');
      }
      const { demo, memoria: mem } = await dados();
      const id = proximoId('leitura', mem);
      const leitura = demo.leituraDeExemplo(id, arquivo?.name);
      mem.leituras.set(id, leitura);
      return copia(leitura);
    },
    responder: (leituraId, respostas) =>
      escrever(leituraId, (demo, leitura) =>
        demo.aplicarRespostas(leitura, respostas)
      ),
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
    async trazer(leituraId) {
      await esperar(atraso);
      const dadosDaDemo = await dados();
      const leitura = leituraDe(dadosDaDemo, leituraId);
      const id = proximoId('trazida', dadosDaDemo.memoria);
      dadosDaDemo.memoria.listas = [
        {
          id,
          arquivo: leitura.arquivo,
          quando: agora(),
          quem: dadosDaDemo.demo.quemTrouxeNaDemo(),
          situacao: SITUACOES_DA_LISTA.TRAZENDO,
          total: totalDaLeitura(leitura),
          novas: resumoAoVivo(leitura).novas,
          completadas: leitura.resumo.completadas,
          receberamCampanha: 0,
        },
        ...dadosDaDemo.memoria.listas,
      ];
      return { trazidaId: id };
    },
    async andamento(trazidaId) {
      const dadosDaDemo = await dados();
      const vista = vistaDaLista(
        listaDe(dadosDaDemo, trazidaId),
        agora(),
        dadosDaDemo.demo
      );
      return {
        porcentagem: vista.porcentagem,
        situacao: vista.situacao,
        total: vista.total,
      };
    },
    async historico() {
      // `?demo=carregando`: o histórico fica no esqueleto, para o print.
      if (demoCarregando()) return esperarParaSempre();
      await esperar(atraso);
      const dadosDaDemo = await dados();
      const momento = agora();
      return dadosDaDemo.memoria.listas.map(lista =>
        vistaDaLista(lista, momento, dadosDaDemo.demo)
      );
    },
    async previaDoDesfazer(trazidaId) {
      await esperar(atraso);
      const lista = listaDe(await dados(), trazidaId);
      return {
        tira: lista.novas,
        devolve: lista.completadas,
        receberamCampanha: lista.receberamCampanha,
      };
    },
    async desfazer(trazidaId) {
      await esperar(atraso);
      const dadosDaDemo = await dados();
      const lista = listaDe(dadosDaDemo, trazidaId);
      const vista = vistaDaLista(lista, agora(), dadosDaDemo.demo);
      // Pronta desfaz sempre, sem data limite; trazendo e desfeita não.
      if (vista.situacao !== SITUACOES_DA_LISTA.PRONTO) {
        throw erroNomeado(
          'NAO_PODE_DESFAZER',
          'Essa lista não pode mais ser desfeita.'
        );
      }
      dadosDaDemo.memoria.listas = dadosDaDemo.memoria.listas.map(item =>
        item.id === trazidaId
          ? { ...item, situacao: SITUACOES_DA_LISTA.DESFEITO }
          : item
      );
      return { id: trazidaId, situacao: SITUACOES_DA_LISTA.DESFEITO };
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
    ler: pendente,
    responder: pendente,
    consertar: pendente,
    deixarDeFora: pendente,
    reabrir: pendente,
    trocarDestino: pendente,
    trazer: pendente,
    andamento: pendente,
    historico: pendente,
    previaDoDesfazer: pendente,
    desfazer: pendente,
  };
};

export const trazerFonte = ({
  demo = null,
  planilha = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
  atrasoDaLeitura = ATRASO_DA_LEITURA_MS,
  agora = Date.now,
} = {}) =>
  demo && carregarDemo
    ? fonteDemo({
        estado: demo,
        planilha: PLANILHAS_DE_DEMO.includes(planilha) ? planilha : null,
        carregarDemo,
        atraso,
        atrasoDaLeitura,
        agora,
      })
    : fonteReal();
