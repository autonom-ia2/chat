// #2896 — a demonstração faz o papel do servidor nas linhas que precisam da
// pessoa (app/services/relacionamentos/trazer/mudar_linha.rb): conserta, deixa
// de fora e volta atrás. Cada função recebe a leitura e devolve uma leitura
// nova, no formato que a fonte real entrega; a que não pode ser feita lança a
// mesma recusa que a fonte real lançaria (demo/trazerRecusa.js).
//   - Consertar: o valor é conferido como no servidor (demo/trazerConserto.js).
//     Se a linha ainda tem outro problema, ela volta aberta com o que sobrou.
//   - A linha `formula` (o erro está num campo que a tela não conserta) recusa
//     qualquer valor: só pode ficar de fora.
//   - Linha repetida: o valor é a linha que fica. Com a outra, esta fica de
//     fora. Com esta, as outras repetidas da mesma pessoa ficam de fora,
//     inclusive a que tinha sido escolhida antes.
//   - Deixar de fora e voltar atrás esquecem o que tinha sido consertado.
// Quantas pessoas entram (`resumo.entram`) é conta daqui, como é do servidor
// (app/services/contact_imports/trazer/quem_entra.rb): as aprovadas na leitura
// mais as consertadas por inteiro. A repetida que a pessoa manteve toma o lugar
// da linha aprovada da mesma pessoa: é uma troca, não uma pessoa a mais.
import {
  copia,
  ehLinhaRepetida,
  problemaDaLeitura,
} from '../fonte/trazerTraducao';
import { SITUACAO_DO_PROBLEMA } from '../trazer/contagem';
import { LIMITES } from '../trazer/limites';
import { TIPO_FORMULA } from '../trazer/textoDoProblema';
import { conferirValor } from './trazerConserto';
import { O_QUE_SOBRA, PROBLEMAS } from './trazerPlanilha';
import { valorInvalido } from './trazerRecusa';

const { ABERTO, GUARDADO, DEIXADO } = SITUACAO_DO_PROBLEMA;
const CHAVE_DO_AVISO = 'aviso';

// ---- as contas que no servidor são dele --------------------------------------

const ficouComEsta = problema =>
  problema.ficar_com !== undefined && problema.ficar_com !== null;

// As linhas consertadas que são uma pessoa a mais.
export const consertadas = leitura =>
  leitura.problemas.filter(
    problema => problema.estado === GUARDADO && !ficouComEsta(problema)
  ).length;

export const comAsContas = leitura => ({
  ...leitura,
  resumo: {
    ...leitura.resumo,
    entram:
      leitura.resumo.novas + leitura.resumo.completadas + consertadas(leitura),
  },
});

// O aviso de uma mudança desfeita vale até a escrita seguinte que dá certo.
export const semAviso = leitura =>
  Object.fromEntries(
    Object.entries(leitura).filter(([chave]) => chave !== CHAVE_DO_AVISO)
  );

// ---- a linha em cada estado ----------------------------------------------------

const DA_PLANILHA = new Map(
  PROBLEMAS.map(problema => [problema.linha, problema])
);
const semMotivo = ({ motivo, ...problema }) => problema;

// Só a linha aberta diz o motivo.
const aberta = linha => ({ ...copia(DA_PLANILHA.get(linha)), estado: ABERTO });
const deixada = linha => ({
  ...semMotivo(copia(DA_PLANILHA.get(linha))),
  estado: DEIXADO,
});
const guardada = (problema, oQueGuardou) => ({
  ...semMotivo(problema),
  estado: GUARDADO,
  ...oQueGuardou,
});

const comAsLinhas = (leitura, novas) => {
  const porLinha = new Map(novas.map(problema => [problema.linha, problema]));
  return comAsContas({
    ...semAviso(leitura),
    problemas: leitura.problemas.map(
      problema => porLinha.get(problema.linha) ?? problema
    ),
  });
};

// ---- consertar -----------------------------------------------------------------

// O problema que a linha ainda tem depois deste conserto, ou null. O contato é
// o que a pessoa acabou de escrever: é por ele que ela acha a linha.
const oQueSobrou = (problema, valor) => {
  const depois = O_QUE_SOBRA.get(problema.linha);
  if (!depois || depois.tipo === problema.tipo) return null;
  return {
    linha: problema.linha,
    ...depois,
    contato: String(valor).trim(),
    estado: ABERTO,
  };
};

const conferir = (leitura, problema, valor) => {
  const { motivo, corrigido } = conferirValor(problema.tipo, valor);
  if (motivo) throw valorInvalido(motivo);
  return comAsLinhas(leitura, [
    oQueSobrou(problema, valor) ?? guardada(problema, { corrigido }),
  ]);
};

const ficarCom = (leitura, problema, escolhida) => {
  const { linha, outraLinha } = problema;
  if (![linha, outraLinha].includes(escolhida)) {
    throw valorInvalido('linha_desconhecida');
  }
  if (escolhida === outraLinha) return comAsLinhas(leitura, [deixada(linha)]);
  const outrasDoGrupo = leitura.problemas.filter(
    outra =>
      ehLinhaRepetida(outra) &&
      outra.outraLinha === outraLinha &&
      outra.linha !== linha
  );
  return comAsLinhas(leitura, [
    guardada(aberta(linha), { ficar_com: linha }),
    ...outrasDoGrupo.map(outra => deixada(outra.linha)),
  ]);
};

// `valor` é o telefone, o e-mail ou o nome certo; na linha repetida, o número
// da linha que fica.
export const aplicarConserto = (leitura, linha, valor) => {
  const problema = problemaDaLeitura(leitura, linha);
  if (String(valor ?? '').length > LIMITES.VALOR) {
    throw valorInvalido('muito_longo');
  }
  if (problema.tipo === TIPO_FORMULA) throw valorInvalido('formula_detected');
  return ehLinhaRepetida(problema)
    ? ficarCom(leitura, problema, valor)
    : conferir(leitura, problema, valor);
};

export const aplicarDeixarDeFora = (leitura, linha) => {
  problemaDaLeitura(leitura, linha);
  return comAsLinhas(leitura, [deixada(linha)]);
};

// "Voltar atrás": a linha volta a ser o problema que a planilha tinha.
export const aplicarReabrir = (leitura, linha) => {
  problemaDaLeitura(leitura, linha);
  return comAsLinhas(leitura, [aberta(linha)]);
};
