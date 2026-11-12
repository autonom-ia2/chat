import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { doServidor } from './doServidor';
import { ATRASO_DA_DEMO_MS, erroFonteRealPendente } from './listaFonte';
import { PLANILHAS_DE_DEMO, fonteDemo } from './trazerFonteDemo';
import {
  SITUACAO_DA_LEITURA,
  STATUS_NAO_ACHEI,
  andamentoDaTela,
  colunaPeloIndice,
  copia,
  corpoDasRespostas,
  corpoDoConserto,
  corpoDoDestino,
  ehLinhaRepetida,
  erroDaEscrita,
  erroDaLeitura,
  erroDaLeituraPendente,
  erroDoEnvio,
  erroNomeado,
  leituraComMaisProblemas,
  leituraComProblema,
  leituraDaTela,
  listaDaTela,
  problemaDaLeitura,
} from './trazerTraducao';
import { SEM_ACESSO } from '../lista/falhas';

// #2894 — de onde "Trazer minha lista" lê e para onde escreve (molde:
// fonte/listaFonte.js). A tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real (#2896): lê a planilha no servidor, grava as respostas das
//      perguntas, conserta ou deixa de fora cada linha (e volta atrás), troca o
//      destino de uma coluna, traz, acompanha o andamento, lista o que já foi
//      trazido e continua a lista que parou no meio
//      (dashboard/api/relacionamentosTrazer.js; a tradução está em
//      trazerTraducao.js). Só o desfazer ainda não existe (Fatia 3): a fonte
//      diz `temDesfazer: false`, a tela não o mostra, e os dois métodos dele
//      respondem `FONTE_REAL_PENDENTE` a quem os chamar mesmo assim.
//      Quem o servidor recusa por falta de permissão (aqui sempre 401)
//      recebe a falha de nome `SEM_ACESSO` (fonte/doServidor.js, o mesmo da
//      lista). As recusas das escritas (422) também ganham nome: o que a
//      pessoa escreveu e ele não aceita é `VALOR_INVALIDO`, com o motivo; o
//      conserto depois que a planilha foi apagada é `PLANILHA_APAGADA`; tirar a
//      última coluna de contato é `TROCA_SEM_CONTATO`; telefone da empresa sem
//      empresa é `SEM_EMPRESA`; trazer sem ninguém para entrar é
//      `NADA_PARA_TRAZER`; a planilha enviada há mais de 7 dias, que já foi
//      apagada, é `CONFERENCIA_VENCIDA` (na escrita e em quem pergunta pela
//      leitura); e o pedido que o servidor já não conhece (a leitura
//      não está pronta ou já foi trazida, a linha, a coluna, a pergunta ou a
//      resposta não existe; e o 404 de qualquer escrita) é
//      `TELA_DESATUALIZADA`. O resto sobe como veio;
//   2. demonstração: com `?demo=<estado>` e só no desenvolvimento
//      (fonte/trazerFonteDemo.js). Ela tem o desfazer (`temDesfazer: true`).
// A leitura que a tela recebe traz os problemas da primeira página e o total
// deles (`problemasTotal`); as outras páginas vêm com `maisProblemas`. Ler
// demora: o servidor responde `lendo` e a fonte pergunta de novo até sair
// disso. Só `ler` e `retomar` esperam. Responder e trocar a coluna devolvem a
// leitura que o servidor mandou ou, quando ele vai ler a planilha de novo, o
// marcador `{ situacao: 'lendo', id }`: a mudança já está salva e quem espera é
// a tela, com `retomar`. A leitura da tela nunca tem a chave `situacao`.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/trazer.js')
  : null;

const ATRASO_DA_LEITURA_MS = 1200;
export { PLANILHAS_DE_DEMO };
export { esquecerMemoriaDaDemo } from './trazerFonteDemo';

// Fonte real: de quanto em quanto tempo pergunta se a leitura da planilha
// terminou, e até quando insiste. Passado o teto, a espera para: a planilha
// continua no servidor e a tela pergunta de novo quando a pessoa pedir.
const INTERVALO_DA_CONSULTA_MS = 1500;
const TETO_DA_CONSULTA_MS = 3 * 60 * 1000;

const esperar = ms =>
  new Promise(resolve => {
    setTimeout(resolve, ms);
  });

// ---- fonte real ------------------------------------------------------------

const PRIMEIRA_PAGINA = 1;
// A falha de quem espera a leitura que não é "ainda não terminou": a leitura
// não existe mais, a pessoa não tem acesso, ou a tela saiu.
const NAO_ADIANTA_ESPERAR = [
  'LEITURA_NAO_ENCONTRADA',
  'LEITURA_INTERROMPIDA',
  SEM_ACESSO,
];

// A leitura que o servidor não acha (já foi trazida, ou não nasceu nesta tela)
// ganha nome: a tela não pergunta de novo.
const leituraNoServidor = async (id, pagina) => {
  try {
    return await doServidor(TrazerAPI.leitura(id, pagina));
  } catch (falha) {
    if (falha?.response?.status !== STATUS_NAO_ACHEI) throw falha;
    throw erroNomeado(
      'LEITURA_NAO_ENCONTRADA',
      'O servidor não achou essa leitura.',
      falha
    );
  }
};

// Toda escrita na leitura (responder, trocar a coluna, mexer numa linha,
// trazer): a recusa do servidor ganha nome (trazerTraducao.js, `erroDaEscrita`).
const escritaNaLeitura = async pedido => {
  try {
    return await doServidor(pedido);
  } catch (falha) {
    throw erroDaEscrita(falha);
  }
};

// As leituras que esta tela já leu, pelo id e já no formato da tela: é nelas
// que a coluna e a linha são conferidas e que entra o que o servidor devolve.
const leiturasGuardadas = () => {
  const leituras = new Map();
  // Até que página de problemas cada leitura já tem.
  const paginas = new Map();

  const guardar = (id, leitura) => {
    leituras.set(id, leitura);
    return copia(leitura);
  };

  // A leitura como o servidor acabou de mandar (a primeira página): toma o
  // lugar da que a fonte tinha.
  const guardarAPrimeiraPagina = (id, resposta) => {
    paginas.set(id, PRIMEIRA_PAGINA);
    return guardar(id, leituraDaTela(resposta));
  };

  const leituraGuardada = id => {
    const leitura = leituras.get(id);
    if (!leitura) {
      throw erroNomeado('LEITURA_NAO_ENCONTRADA', 'Essa leitura não existe.');
    }
    return leitura;
  };

  const paginaSeguinte = id => (paginas.get(id) ?? PRIMEIRA_PAGINA) + 1;

  // A página `pagina` dos problemas, somada aos que a leitura tem agora.
  const guardarMaisUmaPagina = (id, pagina, resposta) => {
    paginas.set(id, pagina);
    return guardar(id, leituraComMaisProblemas(leituraGuardada(id), resposta));
  };

  return {
    guardar,
    guardarAPrimeiraPagina,
    guardarMaisUmaPagina,
    leituraGuardada,
    paginaSeguinte,
  };
};

// Quem espera a leitura sair de `lendo`, até o teto de tempo ou até a tela sair.
const esperaDaLeitura = ({ espera, intervalo, teto, agora }, guardadas) => {
  let encerrada = false;

  const seguir = () => {
    if (encerrada) throw erroNomeado('LEITURA_INTERROMPIDA', 'A tela saiu.');
  };

  // Pergunta de novo até a leitura sair de `lendo`: uma consulta por vez, com a
  // espera entre elas, até o teto de tempo ou até a tela sair.
  const ateSairDeLendo = async (id, limite = agora() + teto) => {
    const resposta = await leituraNoServidor(id, PRIMEIRA_PAGINA);
    seguir();
    if (resposta.situacao !== SITUACAO_DA_LEITURA.LENDO) return resposta;
    if (agora() >= limite) {
      throw erroNomeado('LEITURA_DEMOROU', 'A leitura demorou demais.');
    }
    await espera(intervalo);
    seguir();
    return ateSairDeLendo(id, limite);
  };

  // Só pergunta: espera a leitura sair de `lendo` e devolve a primeira página.
  // Quando a espera falha (o teto passou, ou a rede caiu) a planilha continua
  // no servidor: o erro leva o id, para a tela perguntar de novo depois. A
  // leitura fica guardada pelo id que o servidor manda (o que veio da rota é um
  // texto; as escritas seguintes usam o da leitura).
  const retomar = async id => {
    let resposta;
    try {
      resposta = await ateSairDeLendo(id);
    } catch (falha) {
      throw NAO_ADIANTA_ESPERAR.includes(falha?.name)
        ? falha
        : erroDaLeituraPendente(id, falha);
    }
    if (resposta.situacao !== SITUACAO_DA_LEITURA.PRONTA) {
      throw erroDaLeitura(resposta);
    }
    return guardadas.guardarAPrimeiraPagina(resposta.id ?? id, resposta);
  };

  return {
    retomar,
    // A tela saiu: quem estiver esperando a leitura para de perguntar.
    encerrar() {
      encerrada = true;
    },
  };
};

// As escritas que devolvem a leitura inteira (responder e trocar a coluna) e o
// "Mostrar mais".
const escritasDaLeitura = guardadas => {
  const { leituraGuardada } = guardadas;

  // O que volta de responder e de trocar a coluna: a leitura inteira ou, quando
  // o servidor vai ler a planilha de novo, o marcador (sem esperar).
  const depoisDaEscrita = (id, resposta) =>
    resposta.situacao === SITUACAO_DA_LEITURA.LENDO
      ? { situacao: SITUACAO_DA_LEITURA.LENDO, id }
      : guardadas.guardarAPrimeiraPagina(id, resposta);

  return {
    // A página seguinte dos problemas, somada aos que a leitura tem quando a
    // resposta chega (uma linha pode ter mudado enquanto a página vinha).
    async maisProblemas(leituraId) {
      leituraGuardada(leituraId);
      const pagina = guardadas.paginaSeguinte(leituraId);
      const resposta = await leituraNoServidor(leituraId, pagina);
      if (resposta.situacao === SITUACAO_DA_LEITURA.VENCIDA) {
        throw erroDaLeitura(resposta);
      }
      if (resposta.situacao !== SITUACAO_DA_LEITURA.PRONTA) {
        throw erroNomeado('TELA_DESATUALIZADA', 'A leitura mudou no servidor.');
      }
      return guardadas.guardarMaisUmaPagina(leituraId, pagina, resposta);
    },
    // As respostas das perguntas ("São clientes?" e de quem é o telefone).
    async responder(leituraId, respostas) {
      leituraGuardada(leituraId);
      const corpo = corpoDasRespostas(respostas);
      return depoisDaEscrita(
        leituraId,
        await escritaNaLeitura(TrazerAPI.responder(leituraId, corpo))
      );
    },
    // Coluna de nome, telefone, e-mail ou empresa: o servidor confere a planilha
    // de novo (`lendo`). As outras ele troca na hora e devolve a leitura.
    // A coluna é a do índice (o nome pode repetir ou vir vazio). `campo` é o da
    // informação nova: `{ nome, para_que_serve }`.
    async trocarDestino(leituraId, coluna, destino, campo) {
      const { indice } = colunaPeloIndice(leituraGuardada(leituraId), coluna);
      const corpo = corpoDoDestino(destino, campo);
      return depoisDaEscrita(
        leituraId,
        await escritaNaLeitura(TrazerAPI.trocarColuna(leituraId, indice, corpo))
      );
    },
  };
};

// "Ficar com esta" numa linha repetida deixa de fora, no servidor, todas as
// outras linhas da mesma pessoa (até uma escolha anterior), e a resposta só
// traz a linha tocada: a leitura é pedida de novo. Se esse pedido falha, vale
// a linha que o conserto devolveu (ele já está salvo).
const relerDepoisDeFicarCom = async (guardadas, id, comALinha) => {
  try {
    const resposta = await leituraNoServidor(id, PRIMEIRA_PAGINA);
    return resposta.situacao === SITUACAO_DA_LEITURA.PRONTA
      ? guardadas.guardarAPrimeiraPagina(id, resposta)
      : comALinha;
  } catch {
    return comALinha;
  }
};

// As escritas numa linha que precisa da pessoa.
const escritasDeLinha = guardadas => {
  const { leituraGuardada } = guardadas;

  // O servidor devolve a linha como ficou, que toma o lugar da que a leitura
  // guardada tinha (a planilha não é lida de novo), e quantas pessoas entram
  // agora. Pode ser outro problema da mesma linha: o valor valeu e ficou
  // guardado, mas a linha ainda tem o que resolver.
  const escreverNaLinha = async (id, linha, pedido) => {
    const problema = problemaDaLeitura(leituraGuardada(id), linha);
    const { problema: recebido, entram } = await escritaNaLeitura(
      pedido(problema)
    );
    return guardadas.guardar(
      id,
      leituraComProblema(leituraGuardada(id), { ...recebido, linha }, entram)
    );
  };

  return {
    // `valor` é o telefone, o e-mail ou o nome certo; na linha repetida, o
    // número da linha que fica (com a outra, o servidor deixa esta de fora).
    async consertar(leituraId, linha, valor) {
      const repetida = ehLinhaRepetida(
        problemaDaLeitura(leituraGuardada(leituraId), linha)
      );
      const comALinha = await escreverNaLinha(leituraId, linha, problema =>
        TrazerAPI.consertar(leituraId, linha, corpoDoConserto(problema, valor))
      );
      return repetida
        ? relerDepoisDeFicarCom(guardadas, leituraId, comALinha)
        : comALinha;
    },
    deixarDeFora: (leituraId, linha) =>
      escreverNaLinha(leituraId, linha, () =>
        TrazerAPI.deixarDeFora(leituraId, linha)
      ),
    reabrir: (leituraId, linha) =>
      escreverNaLinha(leituraId, linha, () =>
        TrazerAPI.reabrir(leituraId, linha)
      ),
  };
};

const pendente = async () => {
  throw erroFonteRealPendente();
};

// As listas que a conta já trouxe e a que está sendo trazida.
const listasTrazidas = () => ({
  // Fecha a conferência no servidor; a lista trazida tem o id da leitura.
  async trazer(leituraId) {
    const resposta = await escritaNaLeitura(TrazerAPI.trazer(leituraId));
    return { trazidaId: resposta?.trazidaId ?? leituraId };
  },
  // A lista que parou no meio continua de onde parou.
  async tentarDeNovo(trazidaId) {
    await doServidor(TrazerAPI.confirmar(trazidaId));
    return { trazidaId };
  },
  async andamento(trazidaId) {
    return andamentoDaTela(await doServidor(TrazerAPI.andamento(trazidaId)));
  },
  async historico() {
    const listas = await doServidor(TrazerAPI.listas());
    return listas.map(listaDaTela);
  },
  previaDoDesfazer: pendente,
  desfazer: pendente,
});

const fonteReal = opcoes => {
  const guardadas = leiturasGuardadas();
  const { retomar, encerrar } = esperaDaLeitura(opcoes, guardadas);
  return {
    usaDemo: false,
    // O desfazer fica para a Fatia 3: a tela não mostra o que a conta não tem.
    temDesfazer: false,
    encerrar,
    // Envia a planilha e espera a leitura. O envio que deu certo não se repete:
    // se a espera falha, o erro `LEITURA_PENDENTE` leva o id para o `retomar`.
    async ler(arquivo) {
      let enviada;
      try {
        enviada = await doServidor(TrazerAPI.enviar(arquivo));
      } catch (falha) {
        throw erroDoEnvio(falha);
      }
      return retomar(enviada.id);
    },
    retomar,
    ...escritasDaLeitura(guardadas),
    ...escritasDeLinha(guardadas),
    ...listasTrazidas(),
  };
};

// `espera`, `intervaloDaConsulta` e `tetoDaConsulta` são da fonte real: quem
// testa troca a espera para não dormir de verdade.
export const trazerFonte = ({
  demo = null,
  planilha = null,
  carregarDemo = CARREGAR_DEMO,
  atraso = ATRASO_DA_DEMO_MS,
  atrasoDaLeitura = ATRASO_DA_LEITURA_MS,
  agora = Date.now,
  espera = esperar,
  intervaloDaConsulta = INTERVALO_DA_CONSULTA_MS,
  tetoDaConsulta = TETO_DA_CONSULTA_MS,
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
    : fonteReal({
        espera,
        intervalo: intervaloDaConsulta,
        teto: tetoDaConsulta,
        agora,
      });
