// #2896 — a tradução entre o servidor e a tela de "Trazer minha lista", em
// funções puras (quem fala com o servidor é fonte/trazerFonte.js). O servidor já
// responde quase no formato da tela; aqui fica só o que muda de nome ou de forma:
//   - a leitura perde a paginação: fica com os problemas da primeira página e
//     com o total deles (`problemasTotal`); as outras páginas entram a pedido;
//   - a recusa do envio e a leitura que falhou ganham nome, para a tela escolher
//     a frase sem olhar código de HTTP;
//   - o telefone dos exemplos vem sem formato (+5511987650001) e sai como a
//     pessoa lê; o valor de cada problema fica como está na planilha;
//   - quem identifica a coluna é o índice dela na planilha: o nome pode repetir
//     ou vir vazio;
//   - a lista do histórico troca a data por milissegundos e `pode_tentar` por
//     `podeTentar`; `desfazendo` chega como `desfeito` (a tela ainda não tem esse
//     selo);
//   - (Fatia 2) as respostas das perguntas trocam `coluna_cliente` por
//     `colunaCliente`; o conserto de uma linha vira `{ valor }` ou
//     `{ ficar_com }`, e a linha que volta (o servidor devolve a linha inteira)
//     toma o lugar da que a leitura tinha; a informação nova leva o nome do
//     campo e o "para que serve" (que a tela guarda como o servidor manda:
//     `campo: { nome, para_que_serve }`);
//   - (Fatia 2) `tem_empresa` vira `temEmpresa`: se o telefone da empresa
//     existe nesta leitura;
//   - (Fatia 2) as recusas das escritas (422 com `error`, ou 404) ganham nome,
//     para a tela escolher a frase sem olhar código do servidor;
//   - (Fatia 2) quantas pessoas entram quem diz é o servidor (`resumo.entram`,
//     e `entram` na resposta de cada escrita numa linha): a tela não refaz a
//     conta;
//   - (Fatia 2) `aviso` vem quando o servidor desfez a última mudança.
import { formatarTelefone } from '../lista/telefone';
import { DESTINOS, aparado } from '../trazer/destinos';
import { RESPOSTA_ALGUMAS } from '../trazer/respostas';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

export const SITUACAO_DA_LEITURA = {
  LENDO: 'lendo',
  PRONTA: 'pronta',
  FALHOU: 'falhou',
  // A planilha foi enviada há mais de 7 dias sem ser trazida: já foi apagada.
  VENCIDA: 'vencida',
};

const DESFAZENDO = 'desfazendo';
export const STATUS_NAO_ACHEI = 404;

export const erroNomeado = (nome, mensagem, causa) =>
  Object.assign(new Error(mensagem, causa ? { cause: causa } : undefined), {
    name: nome,
  });

// O servidor já tem a planilha e ainda não terminou de ler (o teto de tempo
// passou, ou a rede caiu no meio da espera): a tela guarda o id e pergunta de
// novo depois, sem enviar o arquivo outra vez.
export const erroDaLeituraPendente = (leituraId, causa) =>
  Object.assign(
    erroNomeado(
      'LEITURA_PENDENTE',
      'O servidor ainda não terminou de ler a planilha.',
      causa
    ),
    { leituraId }
  );

// ---- a leitura da planilha -------------------------------------------------

export const copia = valor => JSON.parse(JSON.stringify(valor ?? null));

const exemploDaTela = exemplo => ({
  ...exemplo,
  telefone: formatarTelefone(exemplo.telefone),
});

// ---- as respostas das perguntas --------------------------------------------

const respondido = valor => valor !== undefined && valor !== null;
const soRespondidas = respostas =>
  Object.fromEntries(
    Object.entries(respostas).filter(([, valor]) => respondido(valor))
  );

// O índice da coluna pode ser 0 (a primeira da planilha): vale como resposta.
export const respostasDaTela = (respostas = {}) =>
  soRespondidas({
    clientes: respostas?.clientes,
    colunaCliente: respostas?.coluna_cliente,
    telefone: respostas?.telefone,
  });

// A coluna que diz quem é cliente só vai quando a resposta é "algumas".
export const corpoDasRespostas = (respostas = {}) =>
  soRespondidas({
    clientes: respostas.clientes,
    coluna_cliente:
      respostas.clientes === RESPOSTA_ALGUMAS
        ? respostas.colunaCliente
        : undefined,
    telefone: respostas.telefone,
  });

// O telefone da empresa só existe quando a planilha tem coluna de empresa e a
// conta tem Empresas: a leitura diz (`tem_empresa`), e a tela não oferece o que
// não existe. Este é o único lugar que lê o campo. Sem ele, vale como
// disponível: se não for, o servidor recusa com `sem_empresa`.
const CAMPO_TEM_EMPRESA = 'tem_empresa';
const temEmpresaNaResposta = resposta => resposta[CAMPO_TEM_EMPRESA] !== false;

// A leitura pronta como o servidor a manda (o GET, e também a resposta inteira
// de responder e de trocar a coluna): os problemas são os da primeira página e
// `problemasTotal` diz quantos há ao todo. `aviso` só existe quando o servidor
// o manda (ele desfez a última mudança).
export const leituraDaTela = resposta => {
  const problemas = copia(resposta.problemas) ?? [];
  return {
    id: resposta.id,
    arquivo: resposta.arquivo,
    valores: resposta.valores,
    temEmpresa: temEmpresaNaResposta(resposta),
    colunas: copia(resposta.colunas) ?? [],
    perguntas: copia(resposta.perguntas) ?? [],
    respostas: respostasDaTela(resposta.respostas),
    resumo: copia(resposta.resumo) ?? {},
    exemplos: (copia(resposta.exemplos) ?? []).map(exemploDaTela),
    problemas,
    problemasTotal: resposta.problemas_total ?? problemas.length,
    ...(resposta.aviso ? { aviso: resposta.aviso } : {}),
  };
};

// "Mostrar mais": os problemas da página seguinte entram depois dos que a
// leitura já tem (a linha que já está na tela não entra duas vezes).
export const leituraComMaisProblemas = (leitura, resposta) => {
  const jaTem = new Set(leitura.problemas.map(problema => problema.linha));
  const novos = (copia(resposta.problemas) ?? []).filter(
    problema => !jaTem.has(problema.linha)
  );
  return {
    ...leitura,
    problemas: [...leitura.problemas, ...novos],
    problemasTotal: resposta.problemas_total ?? leitura.problemasTotal,
  };
};

// O envio que o servidor recusa (422 com `error`).
const NOME_DA_RECUSA_DO_ENVIO = new Map([
  ['tipo', 'PLANILHA_TIPO'],
  ['arquivo_grande', 'PLANILHA_GRANDE'],
]);

export const erroDoEnvio = falha => {
  const nome = NOME_DA_RECUSA_DO_ENVIO.get(falha?.response?.data?.error);
  return nome
    ? erroNomeado(nome, 'O servidor recusou a planilha.', falha)
    : falha;
};

// A leitura que terminou em `falhou`, com o porquê em `erro`.
const NOME_DA_LEITURA_QUE_FALHOU = new Map([
  ['vazia', 'PLANILHA_VAZIA'],
  ['sem_contato', 'PLANILHA_SEM_CONTATO'],
]);
const CONFERENCIA_VENCIDA = 'CONFERENCIA_VENCIDA';

// A leitura que não está pronta nem sendo lida: a que venceu (o mesmo nome que
// a escrita nela recebe, em `erroDaEscrita`) ou a que falhou.
export const erroDaLeitura = resposta =>
  resposta?.situacao === SITUACAO_DA_LEITURA.VENCIDA
    ? erroNomeado(CONFERENCIA_VENCIDA, 'A conferência desta planilha venceu.')
    : erroNomeado(
        NOME_DA_LEITURA_QUE_FALHOU.get(resposta?.erro) ?? 'LEITURA_FALHOU',
        'O servidor não conseguiu ler a planilha.'
      );

// ---- as colunas ------------------------------------------------------------

export const colunaPeloIndice = (leitura, indice) => {
  const coluna = leitura.colunas.find(item => item.indice === indice);
  if (!coluna) {
    throw erroNomeado('COLUNA_NAO_ENCONTRADA', 'Essa coluna não existe.');
  }
  return coluna;
};

// Só a informação nova leva campo: o nome dele e o "para que serve" (opcional).
export const corpoDoDestino = (destino, campo) =>
  destino === DESTINOS.INFORMACAO && campo
    ? {
        destino,
        nome: aparado(campo.nome),
        para_que_serve: aparado(campo.para_que_serve),
      }
    : { destino };

// ---- as recusas das escritas ------------------------------------------------

// O servidor recusa uma escrita com 422 e o código em `error`:
//   - `valor_invalido`: o que a pessoa escreveu não vale (o conserto de uma
//     linha, o nome do campo, o "para que serve"). O erro leva o `motivo`, no
//     código da leitura da planilha, para a tela dizer a frase certa
//     (trazer/recusaDoConserto.js);
//   - `sem_contato`: a escrita tiraria a última coluna de telefone ou e-mail
//     (trocar o destino dela, ou responder "não usar" na pergunta do telefone);
//   - `sem_empresa`: telefone da empresa numa leitura sem empresa;
//   - `planilha_apagada`: o conserto de uma linha depois que a planilha saiu do
//     servidor;
//   - `nada_para_trazer`: trazer sem nenhuma linha aprovada nem consertada;
//   - `conferencia_vencida`: a planilha foi enviada há mais de 7 dias e já foi
//     apagada (toda escrita e o trazer);
//   - os outros: a tela pediu algo que o servidor já não tem (a leitura não
//     está pronta ou já foi trazida, a linha, a coluna, a pergunta ou a resposta
//     não existe). A tela só oferece o que existe, então isso é tela
//     desatualizada, não erro de quem está usando: ela lê a leitura de novo.
//     Vale o mesmo para o 404 (a leitura já foi trazida) e para a linha
//     repetida que o servidor não conhece (`valor_invalido` com o motivo
//     `linha_desconhecida`).
// O que não está aqui sobe como veio.
const RECUSA_DO_VALOR = 'valor_invalido';
const MOTIVO_LINHA_DESCONHECIDA = 'linha_desconhecida';
const TELA_DESATUALIZADA = 'TELA_DESATUALIZADA';
const NOME_DA_RECUSA = new Map([
  ['sem_contato', 'TROCA_SEM_CONTATO'],
  ['sem_empresa', 'SEM_EMPRESA'],
  ['planilha_apagada', 'PLANILHA_APAGADA'],
  ['nada_para_trazer', 'NADA_PARA_TRAZER'],
  ['conferencia_vencida', CONFERENCIA_VENCIDA],
  ['leitura_nao_pronta', TELA_DESATUALIZADA],
  ['linha_desconhecida', TELA_DESATUALIZADA],
  ['resposta_desconhecida', TELA_DESATUALIZADA],
  ['pergunta_desconhecida', TELA_DESATUALIZADA],
  ['coluna_desconhecida', TELA_DESATUALIZADA],
  ['destino_desconhecido', TELA_DESATUALIZADA],
]);

const telaDesatualizada = falha =>
  erroNomeado(
    TELA_DESATUALIZADA,
    'O servidor já não tem o que a tela pediu.',
    falha
  );

const ehValorRecusado = dados => dados?.error === RECUSA_DO_VALOR;

export const erroDaEscrita = falha => {
  const dados = falha?.response?.data;
  const linhaSumiu =
    ehValorRecusado(dados) && dados.motivo === MOTIVO_LINHA_DESCONHECIDA;
  if (falha?.response?.status === STATUS_NAO_ACHEI || linhaSumiu) {
    return telaDesatualizada(falha);
  }
  if (ehValorRecusado(dados)) {
    return Object.assign(
      erroNomeado('VALOR_INVALIDO', 'O servidor não aceitou o valor.', falha),
      { motivo: dados.motivo ?? '' }
    );
  }
  const nome = NOME_DA_RECUSA.get(dados?.error);
  if (nome === TELA_DESATUALIZADA) return telaDesatualizada(falha);
  return nome
    ? erroNomeado(nome, 'O servidor recusou a escrita.', falha)
    : falha;
};

// ---- as linhas que precisam da pessoa ---------------------------------------

const LINHA_REPETIDA = 'duplicada';

export const ehLinhaRepetida = problema => problema.tipo === LINHA_REPETIDA;

export const problemaDaLeitura = (leitura, linha) => {
  const problema = leitura.problemas.find(item => item.linha === linha);
  if (!problema) {
    throw erroNomeado('LINHA_NAO_ENCONTRADA', 'Essa linha não existe.');
  }
  return problema;
};

// Na linha repetida a pessoa escolhe qual das duas fica; nas outras, escreve o
// valor certo.
export const corpoDoConserto = (problema, valor) =>
  ehLinhaRepetida(problema) ? { ficar_com: valor } : { valor };

// O aviso de que a última mudança foi desfeita vale até a escrita seguinte que
// dá certo.
const semOAviso = leitura =>
  Object.fromEntries(
    Object.entries(leitura).filter(([chave]) => chave !== 'aviso')
  );

// O servidor devolve a linha inteira, como a tela a mostra agora: ela toma o
// lugar da que a leitura tinha, sem herdar nada. A linha guardada traz o valor
// como vai ser gravado (`corrigido`) ou a linha repetida que ficou
// (`ficar_com`); a que volta aberta ou deixada de fora, não. E quando o valor
// vale mas a linha ainda tem outro problema, volta esse outro problema (outro
// `tipo`, `estado` aberto): o cartão da linha passa a ser o dele. `entram` é
// quantas pessoas entram agora, na conta do servidor.
export const leituraComProblema = (leitura, recebido, entram) => ({
  ...semOAviso(leitura),
  resumo: { ...leitura.resumo, entram },
  problemas: leitura.problemas.map(problema =>
    problema.linha === recebido.linha ? copia(recebido) : problema
  ),
});

// ---- as listas que a conta já trouxe ---------------------------------------

const situacaoDaTela = situacao =>
  situacao === DESFAZENDO ? SITUACOES_DA_LISTA.DESFEITO : situacao;

export const listaDaTela = lista => ({
  id: lista.id,
  arquivo: lista.arquivo,
  quando: Date.parse(lista.quando),
  // Quem trouxe pode já ter saído da conta.
  quem: lista.quem ?? '',
  total: lista.total,
  situacao: situacaoDaTela(lista.situacao),
  porcentagem: lista.porcentagem,
  podeTentar: lista.pode_tentar === true,
});

export const andamentoDaTela = andamento => ({
  porcentagem: andamento.porcentagem,
  situacao: situacaoDaTela(andamento.situacao),
  total: andamento.total,
  novas: andamento.novas,
  completadas: andamento.completadas,
});
