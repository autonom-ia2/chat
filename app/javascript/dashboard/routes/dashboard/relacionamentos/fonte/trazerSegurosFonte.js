import { ref } from 'vue';
import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { doServidor } from './doServidor';
import {
  SITUACAO_DA_LEITURA,
  andamentoDaTela,
  copia,
  erroDaEscrita,
  erroNomeado,
  leituraComProblema,
} from './trazerTraducao';
import {
  SO_PESSOAS,
  TEM_SEGUROS,
  destinosQueFaltam,
  ehApoliceRepetida,
  segurosConferidos,
} from '../carteira/segurosDaPlanilha';
import { SITUACAO_DO_PROBLEMA } from '../trazer/contagem';

// #2897 — a fonte de "Trazer minha lista" na conta que tem a carteira de
// seguros. Não é outra fonte: é a das listas (fonte/trazerFonte.js) com o que a
// planilha de seguros pede por cima, e a tela a usa do mesmo jeito
// (trazer/useTrazerLista.js). Só existe para a conta de seguros: as outras
// ficam com a fonte das listas, sem nada daqui (pages/TrazerListaPage.vue).
// O que muda:
//   - a resposta de "Esta planilha tem seguros?" vai junto das outras; a
//     leitura volta com o bloco `seguros` (fonte/trazerTraducao.js);
//   - a apólice que aparece em duas linhas com dados diferentes é escolhida
//     com `ficar_com`, e a leitura é pedida de novo (a outra linha muda junto);
//   - depois de mexer numa linha, quantos seguros entram, de quantas pessoas e
//     de que tipo quem diz é o servidor: a fonte pede os números de novo, sem
//     tirar da tela as linhas que a pessoa já tinha carregado;
//   - o trazer que o servidor recusa por faltar coluna do seguro é tela
//     desatualizada (a tela não pede o trazer com coluna faltando): ela lê a
//     leitura de novo e mostra o que falta;
//   - o andamento da lista que trouxe seguros diz quantos seguros chegaram e
//     de quantas pessoas; `chegaram()` devolve o último que a fonte viu.
// Em demonstração (só no desenvolvimento) quem faz o papel do servidor é
// demo/trazerSeguros.js, por cima da demonstração das listas, com as mesmas
// chaves (specs/carteira/paridadeDoTrazerSeguros.spec.js).
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/trazerSeguros.js')
  : null;

const { LENDO, PRONTA } = SITUACAO_DA_LEITURA;
const { ABERTO, DEIXADO } = SITUACAO_DO_PROBLEMA;
const PRIMEIRA_PAGINA = 1;
const FALTA_COLUNA_DO_SEGURO = 'falta_coluna_do_seguro';
const RESPOSTAS = [TEM_SEGUROS, SO_PESSOAS];

// A escrita que faz o servidor ler a planilha de novo devolve só o marcador.
const ehMarcador = resultado => resultado?.situacao === LENDO;
const marcador = id => ({ situacao: LENDO, id });

const telaDesatualizada = causa =>
  erroNomeado(
    'TELA_DESATUALIZADA',
    'O servidor já não tem o que a tela pediu.',
    causa
  );

// ---- o andamento da lista que trouxe seguros --------------------------------

const CONTAS_DO_ANDAMENTO = [
  'seguros',
  'pessoas',
  'pessoasNovas',
  'pessoasQueJaEstavam',
];

// Só a lista que trouxe seguros tem essas contas.
export const contasDosSeguros = andamento =>
  Number.isInteger(andamento?.seguros)
    ? Object.fromEntries(
        CONTAS_DO_ANDAMENTO.map(chave => [chave, andamento[chave]])
      )
    : null;

// A tela das listas só lê do andamento a barra e a situação: o que chegou de
// seguros fica guardado aqui, para a tela da carteira dizer no fim. É um `ref`:
// quem lê `chegaram()` dentro de um `computed` é avisado quando a conta chega.
const lembrandoOQueChegou = fonte => {
  const ultimas = ref(null);
  return {
    ...fonte,
    async andamento(trazidaId) {
      const andamento = await fonte.andamento(trazidaId);
      ultimas.value = contasDosSeguros(andamento);
      return andamento;
    },
    chegaram: () => (ultimas.value ? { ...ultimas.value } : null),
  };
};

// ---- fonte real ---------------------------------------------------------------

const fonteReal = listas => {
  // A leitura que a tela tem agora e os números que o servidor mandou por
  // último, pelo id da leitura.
  const vistas = new Map();
  const resumos = new Map();

  const comOsNumeros = (leitura, resumo) => {
    const vista = { ...leitura, resumo: copia(resumo) };
    resumos.set(leitura.id, vista.resumo);
    vistas.set(leitura.id, vista);
    return copia(vista);
  };

  // A leitura como o servidor acabou de mandar: os números são os dela.
  const fresca = resultado =>
    ehMarcador(resultado)
      ? resultado
      : comOsNumeros(resultado, resultado.resumo);

  // A escrita na linha já está salva. Se o pedido dos números falha, a tela
  // fica com os que tinha (quem chama acerta os seguros pelo `entram`).
  const resumoDeAgora = async id => {
    try {
      const resposta = await doServidor(TrazerAPI.leitura(id, PRIMEIRA_PAGINA));
      return resposta.situacao === PRONTA ? resposta.resumo : null;
    } catch {
      return null;
    }
  };

  // A fonte das listas devolve a leitura com a linha trocada e quantas entram.
  // Na planilha com seguros conferidos, um seguro é uma linha que entra; de
  // quantas pessoas e de que tipo, só o servidor sabe.
  const depoisDaLinha = async (id, leitura) => {
    if (!segurosConferidos(leitura)) {
      return comOsNumeros(leitura, leitura.resumo);
    }
    const resumo = (await resumoDeAgora(id)) ?? {
      ...leitura.resumo,
      seguros: leitura.resumo.entram,
    };
    return comOsNumeros(leitura, resumo);
  };

  // A apólice repetida: a linha escolhida fica e a outra sai, no servidor. A
  // resposta só traz a linha tocada, então a leitura é pedida de novo; se esse
  // pedido falha, vale a linha que a escolha devolveu (ela já está salva).
  const ficarCom = async (id, linha, escolhida) => {
    let resposta;
    try {
      resposta = await doServidor(
        TrazerAPI.consertar(id, linha, { ficar_com: escolhida })
      );
    } catch (falha) {
      throw erroDaEscrita(falha);
    }
    const { problema, entram, clientes } = resposta;
    const comALinha = leituraComProblema(
      vistas.get(id),
      { ...problema, linha },
      entram,
      clientes
    );
    try {
      return fresca(await listas.retomar(id));
    } catch {
      return depoisDaLinha(id, comALinha);
    }
  };

  const problemaDaLinha = (id, linha) =>
    vistas.get(id)?.problemas.find(problema => problema.linha === linha);

  return {
    ...listas,
    ler: async arquivo => fresca(await listas.ler(arquivo)),
    retomar: async id => fresca(await listas.retomar(id)),
    responder: async (id, respostas) =>
      fresca(await listas.responder(id, respostas)),
    trocarDestino: async (id, coluna, destino, campo) =>
      fresca(await listas.trocarDestino(id, coluna, destino, campo)),
    // Mais uma página das linhas: os números continuam os últimos do servidor.
    async maisProblemas(id) {
      const leitura = await listas.maisProblemas(id);
      return comOsNumeros(leitura, resumos.get(id) ?? leitura.resumo);
    },
    async consertar(id, linha, valor) {
      return ehApoliceRepetida(problemaDaLinha(id, linha))
        ? ficarCom(id, linha, valor)
        : depoisDaLinha(id, await listas.consertar(id, linha, valor));
    },
    deixarDeFora: async (id, linha) =>
      depoisDaLinha(id, await listas.deixarDeFora(id, linha)),
    reabrir: async (id, linha) =>
      depoisDaLinha(id, await listas.reabrir(id, linha)),
    async trazer(id) {
      try {
        return await listas.trazer(id);
      } catch (falha) {
        throw falha?.response?.data?.error === FALTA_COLUNA_DO_SEGURO
          ? telaDesatualizada(falha)
          : falha;
      }
    },
    // O andamento como o servidor manda, com as contas dos seguros quando a
    // lista os trouxe.
    async andamento(trazidaId) {
      const andamento = await doServidor(TrazerAPI.andamento(trazidaId));
      return {
        ...andamentoDaTela(andamento),
        ...(contasDosSeguros(andamento) ?? {}),
      };
    },
  };
};

// ---- demonstração -------------------------------------------------------------

// O que a demonstração lembra dos seguros de cada leitura fica na memória do
// módulo, como a demonstração das listas faz com as leituras dela: a leitura
// das pessoas (`base`) e o que a pessoa decidiu sobre os seguros (`seguros`).
let memoria = null;

export const esquecerOsSegurosDaDemo = () => {
  memoria = null;
};

const memoriaDa = estado => {
  if (memoria?.estado !== estado) {
    memoria = { estado, leituras: new Map(), trazidas: new Map() };
  }
  return memoria;
};

const guardadaDe = (dados, id) => {
  const guardada = dados.memoria.leituras.get(id);
  if (!guardada) {
    throw erroNomeado('LEITURA_NAO_ENCONTRADA', 'Essa leitura não existe.');
  }
  return guardada;
};

// A linha de seguro com problema só pode ficar de fora: a recusa é a do servidor.
const consertoNaPlanilha = () =>
  Object.assign(
    erroNomeado('VALOR_INVALIDO', 'O servidor não aceitou o valor.'),
    { motivo: 'conserto_na_planilha' }
  );

const fonteDeDemonstracao = ({ estado, listas, carregarDemo }) => {
  const dados = async () => ({
    demo: await carregarDemo(),
    memoria: memoriaDa(estado),
  });

  // A leitura das pessoas que a demonstração das listas devolveu, com os
  // seguros por cima.
  const vista = async (id, base) => {
    const { demo, memoria: lembrada } = await dados();
    const seguros = lembrada.leituras.get(id)?.seguros ?? demo.estadoInicial();
    lembrada.leituras.set(id, { base, seguros });
    return copia(demo.comSeguros(base, seguros));
  };

  const comOResultado = (id, resultado) =>
    ehMarcador(resultado) ? resultado : vista(id, resultado);

  // Muda o que a demonstração lembra dos seguros e devolve a leitura como fica.
  const comOsSeguros = async (id, mudanca) => {
    const daDemo = await dados();
    const guardada = guardadaDe(daDemo, id);
    const seguros = mudanca(guardada);
    daDemo.memoria.leituras.set(id, { ...guardada, seguros });
    return copia(daDemo.demo.comSeguros(guardada.base, seguros));
  };

  const leituras = {
    // A planilha nova começa sem nada decidido sobre os seguros.
    async ler(arquivo) {
      const base = await listas.ler(arquivo);
      (await dados()).memoria.leituras.delete(base.id);
      return vista(base.id, base);
    },
    retomar: async id => vista(id, await listas.retomar(id)),
    maisProblemas: async id => vista(id, await listas.maisProblemas(id)),
  };

  const escritas = {
    // A resposta dos seguros que muda faz o servidor ler a planilha de novo.
    async responder(id, { seguros: resposta, ...dasPessoas }) {
      const antes = guardadaDe(await dados(), id).seguros.resposta;
      if (resposta !== undefined && !RESPOSTAS.includes(resposta)) {
        throw telaDesatualizada();
      }
      const resultado = await listas.responder(id, dasPessoas);
      const mudou = resposta !== undefined && resposta !== antes;
      if (mudou) {
        const { demo } = await dados();
        await comOsSeguros(id, ({ base, seguros }) =>
          demo.comAResposta(seguros, resposta, base.colunas.length)
        );
      }
      if (ehMarcador(resultado)) return resultado;
      const leitura = await vista(id, resultado);
      return mudou ? marcador(id) : leitura;
    },
    // O destino de seguro só existe depois do "sim" e é de uma coluna só. A
    // troca que completa as colunas obrigatórias faz ler de novo. A
    // demonstração não refaz a leitura das pessoas por causa de uma coluna de
    // seguro: a coluna só muda de nome na tela.
    async trocarDestino(id, coluna, destino, campo) {
      const daDemo = await dados();
      const { demo } = daDemo;
      const { base, seguros } = guardadaDe(daDemo, id);
      const agora = demo.comSeguros(base, seguros);
      const conhecida = agora.colunas.some(({ indice }) => indice === coluna);
      const dasPessoas = base.colunas.some(({ indice }) => indice === coluna);
      // A coluna que só existe na planilha de seguros da demonstração.
      const soDaCarteira = conhecida && !dasPessoas;
      const trocar = () =>
        comOsSeguros(id, guardada =>
          demo.comODestino(guardada.seguros, coluna, destino)
        );
      if (demo.ehDestinoDeSeguro(destino)) {
        if (seguros.resposta !== TEM_SEGUROS || !conhecida) {
          throw telaDesatualizada();
        }
        const faltava = destinosQueFaltam(agora);
        const leitura = await trocar();
        const completou =
          faltava.length > 0 && destinosQueFaltam(leitura).length === 0;
        return completou ? marcador(id) : leitura;
      }
      if (soDaCarteira) return trocar();
      const resultado = await listas.trocarDestino(id, coluna, destino, campo);
      if (seguros.destinos[coluna]) {
        await comOsSeguros(id, guardada =>
          demo.semODestino(guardada.seguros, coluna)
        );
      }
      return comOResultado(id, resultado);
    },
  };

  // A linha de seguro muda de situação aqui; as outras, na demonstração das
  // listas (`dasListas`).
  const mudarALinha = async (id, linha, situacao, dasListas) => {
    const { demo } = await dados();
    if (!demo.ehLinhaDeSeguro(linha)) {
      return comOResultado(id, await dasListas(id, linha));
    }
    return comOsSeguros(id, guardada =>
      demo.comALinha(guardada.seguros, linha, situacao)
    );
  };

  const linhas = {
    async consertar(id, linha, valor) {
      const { demo } = await dados();
      if (!demo.ehLinhaDeSeguro(linha)) {
        return comOResultado(id, await listas.consertar(id, linha, valor));
      }
      if (!demo.aceitaConserto(linha)) throw consertoNaPlanilha();
      return comOsSeguros(id, guardada =>
        demo.comAEscolha(guardada.seguros, linha, valor)
      );
    },
    deixarDeFora: (id, linha) =>
      mudarALinha(id, linha, DEIXADO, listas.deixarDeFora),
    reabrir: (id, linha) => mudarALinha(id, linha, ABERTO, listas.reabrir),
  };

  const trazidas = {
    // Como a fonte real: o trazer com coluna do seguro faltando é recusado.
    async trazer(id) {
      const daDemo = await dados();
      const { base, seguros } = guardadaDe(daDemo, id);
      const leitura = daDemo.demo.comSeguros(base, seguros);
      if (destinosQueFaltam(leitura).length > 0) throw telaDesatualizada();
      const resultado = await listas.trazer(id);
      if (segurosConferidos(leitura)) {
        daDemo.memoria.trazidas.set(
          resultado.trazidaId,
          daDemo.demo.contasDosSeguros(leitura)
        );
      }
      return resultado;
    },
    async andamento(trazidaId) {
      const andamento = await listas.andamento(trazidaId);
      const contas = (await dados()).memoria.trazidas.get(trazidaId);
      return { ...andamento, ...(contas ?? {}) };
    },
  };

  return { ...listas, ...leituras, ...escritas, ...linhas, ...trazidas };
};

// `listas` é a fonte de "Trazer minha lista" (fonte/trazerFonte.js); `demo`, o
// estado da demonstração (só no desenvolvimento).
export const trazerSegurosFonte = ({
  demo = null,
  listas,
  carregarDemo = CARREGAR_DEMO,
}) =>
  lembrandoOQueChegou(
    listas.usaDemo && carregarDemo
      ? fonteDeDemonstracao({ estado: demo, listas, carregarDemo })
      : fonteReal(listas)
  );
