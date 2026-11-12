import { demoCarregando, esperarParaSempre } from './modoDemo';
import {
  SITUACAO_DA_LEITURA,
  copia,
  erroDaLeitura,
  erroNomeado,
} from './trazerTraducao';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

// #2894 — a fonte de demonstração de "Trazer minha lista" (quem escolhe entre
// ela e a fonte real é fonte/trazerFonte.js). É o que o dono abre para aprovar
// a tela: tem os mesmos métodos da fonte real, devolve o mesmo formato e se
// comporta como o servidor (#2896; specs/trazer/paridadeDaDemonstracao.spec.js).
// O protótipo NÃO lê o arquivo no navegador: qualquer planilha devolve a
// leitura fictícia de demo/trazer.js, que também faz o papel do servidor nas
// escritas (confere o valor de cada conserto, recusa com o mesmo erro com
// nome, diz quantas entram e quantas entram como cliente, acerta as perguntas
// e as respostas quando uma coluna muda, e não traz sem saber quem é cliente). As escritas só ficam na memória do módulo (a lista trazida
// continua lá quando a pessoa sai e volta) e cada método devolve cópias novas.
// Como na fonte real, responder e trocar a coluna devolvem a leitura inteira
// ou, quando o servidor leria a planilha de novo, só o marcador
// `{ situacao: 'lendo', id }`: a leitura nova vem do `retomar`.

// `?planilha=` (só em demonstração): faz a leitura cair num estado que a
// planilha de exemplo não mostra, sem precisar de arquivo de verdade.
//   - `nao_e_planilha`, `vazia`, `sem_contato`, `lendo`: os estados do envio;
//   - `vencida`: a planilha foi enviada há mais de 7 dias e já foi apagada (a
//     leitura volta `CONFERENCIA_VENCIDA`);
//   - `mudanca_desfeita`: a leitura é a de exemplo, mas a troca de coluna que
//     faz ler a planilha de novo é desfeita, como o servidor faz quando com
//     ela não sobraria ninguém: a leitura volta como estava, com o aviso.
const MUDANCA_DESFEITA = 'mudanca_desfeita';
const VENCIDA = 'vencida';
export const PLANILHAS_DE_DEMO = [
  'nao_e_planilha',
  'vazia',
  'sem_contato',
  'lendo',
  VENCIDA,
  MUDANCA_DESFEITA,
];
const ARQUIVOS_DE_MENTIRA = {
  nao_e_planilha: { name: 'foto.png' },
  vazia: { name: 'Planilha vazia.xlsx' },
  sem_contato: { name: 'Sem contato.xlsx' },
};
// A leitura que não fica pronta, como o servidor a responderia.
const LEITURAS_QUE_NAO_FICAM_PRONTAS = {
  vazia: { situacao: SITUACAO_DA_LEITURA.FALHOU, erro: 'vazia' },
  sem_contato: { situacao: SITUACAO_DA_LEITURA.FALHOU, erro: 'sem_contato' },
  [VENCIDA]: { situacao: SITUACAO_DA_LEITURA.VENCIDA },
};

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

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

// O id da leitura é um número, como o do servidor.
const proximoNumero = dados => {
  dados.contador += 1;
  return dados.contador;
};

// ---- a lista na conta: andamento e situação --------------------------------

// A barra anda desde que a lista começou a ser trazida, ou desde que a pessoa
// mandou tentar de novo (o dia em que a lista foi enviada não muda por isso).
const porcentagemDaLista = (lista, agora, demo) =>
  demo.porcentagemDaTrazida(lista.retomadaEm ?? lista.quando, agora);

// O desfazer também leva um tempo: a lista fica `desfazendo` desde o pedido
// (`desfazendoDesde`) e depois aparece `desfeito`.
const situacaoDaLista = (lista, agora, demo) => {
  if (lista.situacao === SITUACOES_DA_LISTA.DESFAZENDO) {
    return demo.desfazerTerminou(lista.desfazendoDesde, agora)
      ? SITUACOES_DA_LISTA.DESFEITO
      : lista.situacao;
  }
  if (lista.situacao !== SITUACOES_DA_LISTA.TRAZENDO) return lista.situacao;
  const porcentagem = porcentagemDaLista(lista, agora, demo);
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
        ? porcentagemDaLista(lista, agora, demo)
        : 100,
    podeTentar: lista.podeTentar === true,
  };
};

// ---- demonstração ----------------------------------------------------------

const leituraDe = (dadosDaDemo, leituraId) => {
  const leitura = dadosDaDemo.memoria.leituras.get(leituraId);
  if (!leitura) {
    throw erroNomeado('LEITURA_NAO_ENCONTRADA', 'Essa leitura não existe.');
  }
  return leitura;
};

const listaDe = (dadosDaDemo, trazidaId) => {
  const lista = dadosDaDemo.memoria.listas.find(item => item.id === trazidaId);
  if (!lista) {
    throw erroNomeado('LISTA_NAO_ENCONTRADA', 'Essa lista não existe.');
  }
  return lista;
};

const guardar = (dadosDaDemo, leituraId, leitura) => {
  dadosDaDemo.memoria.leituras.set(leituraId, leitura);
  return copia(leitura);
};

// Troca a lista `trazidaId` pela que `mudar` devolve.
const trocarALista = (dadosDaDemo, trazidaId, mudar) => {
  dadosDaDemo.memoria.listas = dadosDaDemo.memoria.listas.map(item =>
    item.id === trazidaId ? mudar(item) : item
  );
};

// Ler a planilha, retomar a leitura e o "Mostrar mais".
const leiturasDaDemo = ({ planilha, dados, atraso, atrasoDaLeitura }) => ({
  async ler(arquivo) {
    // `?planilha=lendo`: a leitura nunca termina, para o print do "lendo".
    if (planilha === 'lendo') return esperarParaSempre();
    await esperar(atrasoDaLeitura);
    const naoFicaPronta = LEITURAS_QUE_NAO_FICAM_PRONTAS[planilha];
    if (naoFicaPronta) throw erroDaLeitura(naoFicaPronta);
    const dadosDaDemo = await dados();
    const id = proximoNumero(dadosDaDemo.memoria);
    const leitura = dadosDaDemo.demo.leituraDeExemplo(id, arquivo?.name);
    return guardar(dadosDaDemo, id, leitura);
  },
  // A leitura que a demonstração tem, como está agora: é por aqui que chega
  // a leitura depois de uma escrita que devolveu o marcador `lendo`.
  async retomar(leituraId) {
    await esperar(atrasoDaLeitura);
    return copia(leituraDe(await dados(), leituraId));
  },
  // A leitura de exemplo já vem com todos os problemas: não há mais o que buscar.
  async maisProblemas(leituraId) {
    await esperar(atraso);
    return copia(leituraDe(await dados(), leituraId));
  },
});

// `?planilha=mudanca_desfeita`: a leitura como estava, com o aviso.
const comAMudancaDesfeita = antes => ({ ...antes, aviso: MUDANCA_DESFEITA });

// Os dois jeitos de escrever na leitura da demonstração.
const escritoresDaDemo = ({ dados, atraso }) => {
  // Escrita na leitura: espera um pouco, troca a leitura por uma nova e devolve
  // cópia. A recusa (a função lança) não muda nada.
  const escrever = async (leituraId, mudar) => {
    await esperar(atraso);
    const dadosDaDemo = await dados();
    const nova = mudar(dadosDaDemo.demo, leituraDe(dadosDaDemo, leituraId));
    return guardar(dadosDaDemo, leituraId, nova);
  };
  // A escrita que pode fazer o servidor ler a planilha de novo (`rele`): aí a
  // mudança fica salva e volta só o marcador. `desfeita` é a leitura que fica
  // no lugar quando o servidor desfaz a mudança.
  const escreverRelendo = async (leituraId, mudar, rele, desfeita) => {
    await esperar(atraso);
    const dadosDaDemo = await dados();
    const { demo } = dadosDaDemo;
    const antes = leituraDe(dadosDaDemo, leituraId);
    const nova = mudar(demo, antes);
    if (!rele(demo, antes)) return guardar(dadosDaDemo, leituraId, nova);
    guardar(dadosDaDemo, leituraId, desfeita ? desfeita(antes) : nova);
    return { situacao: SITUACAO_DA_LEITURA.LENDO, id: leituraId };
  };
  return { escrever, escreverRelendo };
};

// As escritas na leitura: as respostas, cada linha e o destino de uma coluna.
const escritasDaDemo = opcoes => {
  const { escrever, escreverRelendo } = escritoresDaDemo(opcoes);
  const seDesfaz =
    opcoes.planilha === MUDANCA_DESFEITA ? comAMudancaDesfeita : null;

  return {
    responder: (leituraId, respostas) =>
      escreverRelendo(
        leituraId,
        (demo, leitura) => demo.aplicarRespostas(leitura, respostas),
        (demo, leitura) => demo.respostaRele(leitura, respostas)
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
    // `coluna` é o índice dela na planilha, como na fonte real.
    trocarDestino: (leituraId, coluna, destino, campo) =>
      escreverRelendo(
        leituraId,
        (demo, leitura) => demo.aplicarDestino(leitura, coluna, destino, campo),
        (demo, leitura) => demo.trocaRele(leitura, coluna, destino),
        seDesfaz
      ),
  };
};

// Trazer a lista, tentar de novo a que parou e o andamento.
const trazidasDaDemo = ({ dados, atraso, agora }) => ({
  async trazer(leituraId) {
    await esperar(atraso);
    const dadosDaDemo = await dados();
    const leitura = leituraDe(dadosDaDemo, leituraId);
    // Como o servidor: sem saber quem é cliente, não traz adivinhando.
    dadosDaDemo.demo.conferirAntesDeTrazer(leitura);
    const id = `trazida-${proximoNumero(dadosDaDemo.memoria)}`;
    const trazida = {
      id,
      arquivo: leitura.arquivo,
      quando: agora(),
      quem: dadosDaDemo.demo.quemTrouxeNaDemo(),
      situacao: SITUACOES_DA_LISTA.TRAZENDO,
      ...dadosDaDemo.demo.contasDaTrazida(leitura),
    };
    dadosDaDemo.memoria.listas = [trazida, ...dadosDaDemo.memoria.listas];
    return { trazidaId: id };
  },
  // A lista que parou no meio volta a ser trazida, com a barra do começo.
  async tentarDeNovo(trazidaId) {
    await esperar(atraso);
    const dadosDaDemo = await dados();
    const lista = listaDe(dadosDaDemo, trazidaId);
    const parou =
      lista.situacao === SITUACOES_DA_LISTA.FALHOU && lista.podeTentar;
    if (!parou) {
      throw erroNomeado('NAO_PODE_TENTAR', 'Essa lista não parou no meio.');
    }
    trocarALista(dadosDaDemo, trazidaId, item => ({
      ...item,
      situacao: SITUACOES_DA_LISTA.TRAZENDO,
      podeTentar: false,
      retomadaEm: agora(),
    }));
    return { trazidaId };
  },
  async andamento(trazidaId) {
    const dadosDaDemo = await dados();
    const lista = listaDe(dadosDaDemo, trazidaId);
    const vista = vistaDaLista(lista, agora(), dadosDaDemo.demo);
    return {
      porcentagem: vista.porcentagem,
      situacao: vista.situacao,
      total: vista.total,
      novas: lista.novas,
      completadas: lista.completadas,
    };
  },
});

// Como o servidor: só a lista que já foi gravada (pronta, sendo desfeita ou
// desfeita) tem prévia e desfazer. A que ainda está sendo trazida e a que
// parou no meio são recusadas. Devolve a lista e a situação dela agora.
const JA_GRAVADA = [
  SITUACOES_DA_LISTA.PRONTO,
  SITUACOES_DA_LISTA.DESFAZENDO,
  SITUACOES_DA_LISTA.DESFEITO,
];

const listaGravada = (dadosDaDemo, trazidaId, agora) => {
  const lista = listaDe(dadosDaDemo, trazidaId);
  const { situacao } = vistaDaLista(lista, agora, dadosDaDemo.demo);
  if (!JA_GRAVADA.includes(situacao)) {
    throw erroNomeado(
      'NAO_PODE_DESFAZER',
      'Essa lista ainda não pode ser desfeita.'
    );
  }
  return { lista, situacao };
};

// O que a conta já trouxe e o desfazer.
const historicoDaDemo = ({ dados, atraso, agora }) => ({
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
    const { lista } = listaGravada(await dados(), trazidaId, agora());
    return {
      tira: lista.novas - lista.ficam,
      ficam: lista.ficam,
      devolve: lista.completadas,
    };
  },
  async desfazer(trazidaId) {
    await esperar(atraso);
    const dadosDaDemo = await dados();
    const momento = agora();
    const { situacao } = listaGravada(dadosDaDemo, trazidaId, momento);
    // Pronta desfaz sempre, sem data limite. O pedido repetido não muda nada:
    // responde a situação de agora (`desfazendo` ou `desfeito`).
    if (situacao !== SITUACOES_DA_LISTA.PRONTO) {
      return { id: trazidaId, situacao };
    }
    trocarALista(dadosDaDemo, trazidaId, item => ({
      ...item,
      situacao: SITUACOES_DA_LISTA.DESFAZENDO,
      desfazendoDesde: momento,
    }));
    return { id: trazidaId, situacao: SITUACOES_DA_LISTA.DESFAZENDO };
  },
});

export const fonteDemo = opcoes => {
  const { estado, planilha, carregarDemo, agora } = opcoes;
  const dados = async () => {
    const demo = await carregarDemo();
    return { demo, memoria: memoriaDa(estado, demo, agora()) };
  };
  const comOsDados = { ...opcoes, dados };
  return {
    usaDemo: true,
    temDesfazer: true,
    planilhaDeDemo: planilha,
    arquivoDeExemplo: () => ARQUIVOS_DE_MENTIRA[planilha] ?? null,
    // A demonstração não fica esperando o servidor: não há o que parar.
    encerrar() {},
    ...leiturasDaDemo(comOsDados),
    ...escritasDaDemo(comOsDados),
    ...trazidasDaDemo(comOsDados),
    ...historicoDaDemo(comOsDados),
  };
};
