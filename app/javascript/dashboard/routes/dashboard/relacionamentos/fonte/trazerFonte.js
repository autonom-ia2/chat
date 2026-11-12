import TrazerAPI from 'dashboard/api/relacionamentosTrazer';
import { ATRASO_DA_DEMO_MS, erroFonteRealPendente } from './listaFonte';
import { demoCarregando, esperarParaSempre } from './modoDemo';
import {
  SITUACAO_DA_LEITURA,
  andamentoDaTela,
  colunaPeloIndice,
  corpoDoDestino,
  erroDaLeitura,
  erroDoEnvio,
  erroNomeado,
  leituraComColunas,
  leituraDaTela,
  listaDaTela,
  paginasDeProblemas,
} from './trazerTraducao';
import { SEM_ACESSO } from '../ficha/falhas';
import { resumoAoVivo, totalDaLeitura } from '../trazer/contagem';
import { DESTINOS } from '../trazer/destinos';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

// #2894 — de onde "Trazer minha lista" lê e para onde escreve (molde:
// fonte/listaFonte.js). A tela recebe sempre o mesmo formato, venha de onde vier:
//   1. fonte real (#2896, Fatia 1): lê a planilha no servidor, troca o destino
//      de uma coluna, traz, acompanha o andamento, lista o que já foi trazido e
//      continua a lista que parou no meio (dashboard/api/relacionamentosTrazer.js;
//      a tradução está em trazerTraducao.js). O que é das próximas fatias ainda
//      diz `FONTE_REAL_PENDENTE`: responder às perguntas, consertar, deixar de
//      fora, voltar atrás e desfazer. Quem o servidor recusa por falta de acesso
//      (401, 403) recebe a falha de nome `SEM_ACESSO`; o resto sobe como veio;
//   2. demonstração: com `?demo=<estado>` e só no desenvolvimento. O protótipo
//      NÃO lê o arquivo no navegador: qualquer planilha devolve a leitura
//      fictícia de demo/trazer.js. As escritas só ficam na memória do módulo
//      (a lista trazida continua lá quando a pessoa sai e volta) e cada método
//      devolve cópias novas.
const CARREGAR_DEMO = import.meta.env.DEV
  ? () => import('../demo/trazer.js')
  : null;

export const ATRASO_DA_LEITURA_MS = 1200;

// Fonte real: de quanto em quanto tempo pergunta se a leitura da planilha
// terminou, e até quando insiste. Passado o teto, a tela mostra o erro de
// leitura (com "tentar de novo") em vez de ficar em "Lendo…" para sempre.
export const INTERVALO_DA_CONSULTA_MS = 1500;
export const TETO_DA_CONSULTA_MS = 3 * 60 * 1000;

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
      const novas = resumoAoVivo(leitura).novas;
      dadosDaDemo.memoria.listas = [
        {
          id,
          arquivo: leitura.arquivo,
          quando: agora(),
          quem: dadosDaDemo.demo.quemTrouxeNaDemo(),
          situacao: SITUACOES_DA_LISTA.TRAZENDO,
          total: totalDaLeitura(leitura),
          novas,
          completadas: leitura.resumo.completadas,
          ficam: dadosDaDemo.demo.ficamNaTrazida(novas),
        },
        ...dadosDaDemo.memoria.listas,
      ];
      return { trazidaId: id };
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
        tira: lista.novas - lista.ficam,
        ficam: lista.ficam,
        devolve: lista.completadas,
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

// ---- fonte real ------------------------------------------------------------

const STATUS_SEM_ACESSO = [401, 403];
const STATUS_NAO_ACHEI = 404;
const PRIMEIRA_PAGINA = 1;
// Destinos que o servidor só conhece na Fatia 2.
const DESTINOS_DA_FATIA_2 = [
  DESTINOS.CIDADE,
  DESTINOS.TELEFONE_DA_EMPRESA,
  DESTINOS.CLIENTE,
];

const comNome = falha =>
  STATUS_SEM_ACESSO.includes(falha?.response?.status)
    ? erroNomeado(SEM_ACESSO, 'Sem acesso a Trazer minha lista.', falha)
    : falha;

// `pedido()` é uma ida ao servidor: devolve o corpo da resposta. A recusa por
// falta de acesso ganha nome; qualquer outro erro sobe como veio.
const noServidor = async pedido => {
  try {
    return (await pedido()).data;
  } catch (falha) {
    throw comNome(falha);
  }
};

// A leitura que o servidor não acha (já foi trazida, ou não nasceu nesta tela)
// ganha nome: a tela mostra o erro de leitura e não pergunta de novo.
const leituraNoServidor = async (id, pagina) => {
  try {
    return await noServidor(() => TrazerAPI.leitura(id, pagina));
  } catch (falha) {
    if (falha?.response?.status !== STATUS_NAO_ACHEI) throw falha;
    throw erroNomeado(
      'LEITURA_NAO_ENCONTRADA',
      'O servidor não achou essa leitura.',
      falha
    );
  }
};

const fonteReal = ({ espera, intervalo, teto, agora }) => {
  // As leituras que esta tela já leu, pelo id e já no formato da tela: é nelas
  // que a coluna é conferida e que entra o que o servidor devolve.
  const leituras = new Map();
  let encerrada = false;

  const pendente = async () => {
    throw erroFonteRealPendente();
  };
  const seguir = () => {
    if (encerrada) {
      throw erroNomeado('LEITURA_INTERROMPIDA', 'A tela saiu.');
    }
  };

  // Pergunta de novo até a leitura sair de `lendo`: uma consulta por vez, com a
  // espera entre elas, até o teto de tempo ou até a tela sair.
  const ateSairDeLendo = async (id, pagina, limite = agora() + teto) => {
    const resposta = await leituraNoServidor(id, pagina);
    seguir();
    if (resposta.situacao !== SITUACAO_DA_LEITURA.LENDO) return resposta;
    if (agora() >= limite) {
      throw erroNomeado('LEITURA_DEMOROU', 'A leitura demorou demais.');
    }
    await espera(intervalo);
    seguir();
    return ateSairDeLendo(id, pagina, limite);
  };

  const paginaPronta = async (id, pagina) => {
    const resposta = await ateSairDeLendo(id, pagina);
    if (resposta.situacao !== SITUACAO_DA_LEITURA.PRONTA) {
      throw erroDaLeitura(resposta);
    }
    return resposta;
  };

  // A leitura pronta, com os problemas de todas as páginas; fica guardada. Uma
  // página por vez: a cada pedido o servidor relê a planilha.
  const leituraPronta = async id => {
    const primeira = await paginaPronta(id, PRIMEIRA_PAGINA);
    const problemas = [...(primeira.problemas ?? [])];
    const paginas = paginasDeProblemas(primeira);
    for (let pagina = PRIMEIRA_PAGINA + 1; pagina <= paginas; pagina += 1) {
      // eslint-disable-next-line no-await-in-loop
      const seguinte = await paginaPronta(id, pagina);
      problemas.push(...(seguinte.problemas ?? []));
    }
    const leitura = leituraDaTela(primeira, problemas);
    leituras.set(id, leitura);
    return copia(leitura);
  };

  const leituraGuardada = id => {
    const leitura = leituras.get(id);
    if (!leitura) {
      throw erroNomeado('LEITURA_NAO_ENCONTRADA', 'Essa leitura não existe.');
    }
    return leitura;
  };

  const confirmar = async id => {
    await noServidor(() => TrazerAPI.confirmar(id));
    return { trazidaId: id };
  };

  return {
    usaDemo: false,
    // A tela saiu: quem estiver esperando a leitura para de perguntar.
    encerrar() {
      encerrada = true;
    },
    async ler(arquivo) {
      let enviada;
      try {
        enviada = await noServidor(() => TrazerAPI.enviar(arquivo));
      } catch (falha) {
        throw erroDoEnvio(falha);
      }
      return leituraPronta(enviada.id);
    },
    // Coluna de nome, telefone, e-mail ou empresa: o servidor confere a planilha
    // de novo (`lendo`). As outras ele troca na hora e devolve só as colunas.
    // A coluna é a do índice (o nome pode repetir ou vir vazio).
    async trocarDestino(leituraId, coluna, destino) {
      if (DESTINOS_DA_FATIA_2.includes(destino)) throw erroFonteRealPendente();
      const leitura = leituraGuardada(leituraId);
      const { indice } = colunaPeloIndice(leitura, coluna);
      const resposta = await noServidor(() =>
        TrazerAPI.trocarColuna(leituraId, indice, corpoDoDestino(destino))
      );
      if (resposta.situacao === SITUACAO_DA_LEITURA.LENDO) {
        return leituraPronta(leituraId);
      }
      const nova = leituraComColunas(leitura, resposta.colunas);
      leituras.set(leituraId, nova);
      return copia(nova);
    },
    trazer: confirmar,
    // A lista que parou no meio continua de onde parou.
    tentarDeNovo: confirmar,
    async andamento(trazidaId) {
      return andamentoDaTela(
        await noServidor(() => TrazerAPI.andamento(trazidaId))
      );
    },
    async historico() {
      const listas = await noServidor(() => TrazerAPI.listas());
      return listas.map(listaDaTela);
    },
    responder: pendente,
    consertar: pendente,
    deixarDeFora: pendente,
    reabrir: pendente,
    previaDoDesfazer: pendente,
    desfazer: pendente,
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
