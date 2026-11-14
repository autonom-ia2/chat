// #2896, E3 — a demonstração faz o papel do servidor na pergunta "Quais destes
// querem dizer cliente?" (o contrato está no brief do E3; no servidor, a conta
// de cada valor sai da leitura da planilha). Tudo aqui é função pura sobre a
// leitura, no formato que a fonte real entrega:
//   - a pergunta existe quando há coluna com destino `cliente` e a resposta de
//     "São clientes?" não é "sim, todas". Traz até 20 valores, do que mais
//     aparece ao que menos aparece, e o resto somado em `outros`;
//   - a chave de cada valor é opaca e vale só para aquela coluna. No servidor
//     é um resumo do valor com segredo; aqui é um texto que não se lê;
//   - a resposta é `{ modo: 'preenchidas' }` ou `{ modo: 'valores', chaves }`.
//     O modo que não existe, a lista de chaves vazia e a chave que não é da
//     coluna são `resposta_desconhecida`; mandar a resposta sem haver coluna
//     de cliente é `pergunta_desconhecida`;
//   - as chaves só valem para a coluna que JÁ dizia quem é cliente antes do
//     pedido: marcar valores no mesmo pedido que troca a coluna é
//     `resposta_desconhecida` (a pessoa ainda não viu os valores da coluna
//     nova). "Toda linha com algo escrito" no mesmo pedido é aceito;
//   - o trazer com a pergunta sem resposta é `falta_valores_cliente`;
//   - quantas entram como cliente (`resumo.clientes`): todas com "sim, todas";
//     sem resposta, nenhuma. Com a resposta, a soma das linhas dos valores
//     marcados, sem passar de quantas pessoas entram (a demonstração não tem
//     as linhas da planilha, uma a uma, para cruzar).
// Nada aqui interpreta o texto da célula: quem diz o que quer dizer cliente é
// a pessoa.
import { DESTINOS } from '../trazer/destinos';
import { PERGUNTA_VALORES } from '../trazer/respostas';
import {
  MODOS,
  chavesMarcadas,
  marcouPreenchidas,
  valorMarcado,
  valoresRespondidos,
} from '../trazer/valoresDeCliente';
import { VALORES_DAS_COLUNAS } from './trazerPlanilha';
import { recusa } from './trazerRecusa';

const MAXIMO_DE_VALORES = 20;
const SIM_TODAS = 'sim_todas';
const NINGUEM = 0;

const chaveDe = (indice, posicao) => `demo-${indice}-${posicao}`;

// Todos os valores da coluna, na ordem da planilha de exemplo.
const valoresDa = indice =>
  (VALORES_DAS_COLUNAS.get(indice) ?? []).map(([valor, linhas], posicao) => ({
    chave: chaveDe(indice, posicao),
    valor,
    linhas,
  }));

const linhasDe = valores =>
  valores.reduce((soma, valor) => soma + valor.linhas, 0);

const colunaDeCliente = colunas =>
  colunas.find(coluna => coluna.destino === DESTINOS.CLIENTE) ?? null;

// O índice da coluna que diz quem é cliente, ou null quando nenhuma diz.
export const indiceDaColunaDeCliente = colunas =>
  colunaDeCliente(colunas)?.indice ?? null;

// A coluna de que a pergunta fala, ou null quando a pergunta não existe.
const colunaDaPergunta = ({ colunas, respostas }) =>
  respostas.clientes === SIM_TODAS ? null : colunaDeCliente(colunas);

export const perguntaDosValores = leitura => {
  const coluna = colunaDaPergunta(leitura);
  if (!coluna) return null;
  const todos = valoresDa(coluna.indice);
  const fora = todos.slice(MAXIMO_DE_VALORES);
  return {
    id: PERGUNTA_VALORES,
    coluna: coluna.nome,
    indice: coluna.indice,
    preenchidas: linhasDe(todos),
    valores: todos.slice(0, MAXIMO_DE_VALORES),
    outros: fora.length
      ? { valores: fora.length, linhas: linhasDe(fora) }
      : null,
  };
};

// ---- responder ------------------------------------------------------------------

const ehDaColuna = (indice, chaves) => {
  const daColuna = valoresDa(indice).map(valor => valor.chave);
  return chaves.every(chave => daColuna.includes(chave));
};

// A resposta como o servidor a guarda: só o modo e, nos valores, as chaves.
// `chavesConhecidas`: a tela já recebeu as chaves desta coluna.
const respostaConferida = (coluna, resposta, chavesConhecidas) => {
  if (marcouPreenchidas(resposta)) return { modo: MODOS.PREENCHIDAS };
  const chaves = chavesMarcadas(resposta);
  const valem =
    chaves.length && chavesConhecidas && ehDaColuna(coluna.indice, chaves);
  if (!valem) throw recusa('resposta_desconhecida');
  return { modo: MODOS.VALORES, chaves: [...chaves] };
};

// `resposta` é o que veio no pedido (sem ela, a leitura fica como está);
// `leitura` já tem as colunas como o pedido as deixa, e `colunaDeAntes` é o
// índice da coluna que dizia quem é cliente antes dele.
export const comOsValores = (leitura, resposta, colunaDeAntes) => {
  if (resposta === undefined || resposta === null) return leitura;
  const coluna = colunaDaPergunta(leitura);
  if (!coluna) throw recusa('pergunta_desconhecida');
  const conferida = respostaConferida(
    coluna,
    resposta,
    coluna.indice === colunaDeAntes
  );
  return {
    ...leitura,
    respostas: { ...leitura.respostas, [PERGUNTA_VALORES]: conferida },
  };
};

// ---- o que a resposta faz ---------------------------------------------------------

export const conferirAntesDeTrazer = leitura => {
  const falta =
    colunaDaPergunta(leitura) &&
    !valoresRespondidos(leitura.respostas[PERGUNTA_VALORES]);
  if (falta) throw recusa('falta_valores_cliente');
};

const marcados = (indice, resposta) =>
  marcouPreenchidas(resposta)
    ? valoresDa(indice)
    : valoresDa(indice).filter(valor => valorMarcado(resposta, valor.chave));

// Quantas das `entram` pessoas entram como cliente.
export const clientesQueEntram = ({ colunas, respostas }, entram) => {
  if (respostas.clientes === SIM_TODAS) return entram;
  const coluna = colunaDeCliente(colunas);
  const resposta = respostas[PERGUNTA_VALORES];
  if (!coluna || !valoresRespondidos(resposta)) return NINGUEM;
  return Math.min(entram, linhasDe(marcados(coluna.indice, resposta)));
};

// A pessoa de exemplo entra como cliente? `celulas` é o que a planilha tem
// escrito para ela em cada coluna (pelo índice).
export const exemploEhCliente = ({ colunas, respostas }, celulas = {}) => {
  if (respostas.clientes === SIM_TODAS) return true;
  const coluna = colunaDeCliente(colunas);
  const resposta = respostas[PERGUNTA_VALORES];
  const celula = coluna ? (celulas[coluna.indice] ?? '') : '';
  if (!celula || !valoresRespondidos(resposta)) return false;
  return marcados(coluna.indice, resposta).some(
    marcado => marcado.valor === celula
  );
};
