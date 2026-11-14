// #2894 — a planilha fictícia de "Trazer minha lista" e as listas que já foram
// trazidas. Só é carregada no ambiente de desenvolvimento (fonte/trazerFonte.js,
// `import.meta.env.DEV`); em produção o arquivo nem entra no pacote.
//
// A demonstração é o que o dono abre para aprovar a tela: ela faz o papel do
// servidor, com o mesmo formato e o mesmo comportamento da fonte real (#2896).
// Este arquivo é a porta de entrada dela (é o que a fonte carrega):
//   - a planilha, como o servidor a teria lido, está em demo/trazerPlanilha.js;
//   - as escritas nas linhas que precisam da pessoa e a conta de quantas
//     entram, em demo/trazerLinhas.js (o valor é conferido em
//     demo/trazerConserto.js);
//   - a troca de destino de uma coluna, as perguntas e as respostas, em
//     demo/trazerColunas.js;
//   - a pergunta "Quais destes querem dizer cliente?", a resposta dela e o
//     trazer que não adivinha, em demo/trazerValores.js.
// Cada escrita é uma função pura: recebe a leitura e devolve uma leitura nova,
// no formato que a fonte real entrega (fonte/trazerTraducao.js), ou lança a
// mesma recusa com nome. Aqui ficam a leitura de exemplo, as listas que a conta
// "já trouxe" e o andamento de uma lista sendo trazida.
import { DIA_EM_MS } from '../fonte/grupos';
import { copia } from '../fonte/trazerTraducao';
import { SITUACAO_DO_PROBLEMA } from '../trazer/contagem';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';
import { exemplosDe } from './trazerColunas';
import { comAsContas, consertadas } from './trazerLinhas';
import {
  COLUNAS,
  NOME_DO_ARQUIVO_DE_EXEMPLO,
  PERGUNTAS,
  PROBLEMAS,
  RESUMO,
} from './trazerPlanilha';

export {
  aplicarDestino,
  aplicarRespostas,
  respostaRele,
  trocaRele,
} from './trazerColunas';
export {
  aplicarConserto,
  aplicarDeixarDeFora,
  aplicarReabrir,
} from './trazerLinhas';
export { conferirAntesDeTrazer } from './trazerValores';

// Quanto a lista leva para entrar. A tela pergunta pelo andamento com a espera
// crescendo (trazer/consultaComRecuo.js: aos 0 s, 1,5 s, 3,75 s, 7,1 s, 12,1 s
// e 17,1 s): em 17 segundos a barra passa por 0, 8, 22, 41 e 71 antes de
// terminar, em vez de pular de 25 para 62 e acabar.
export const DURACAO_DA_TRAZIDA_MS = 17000;
// Quanto o desfazer leva: a linha do histórico passa por "Desfazendo…" (uma
// pergunta, aos 1,5 s) antes de virar "Desfeito" (na seguinte, aos 3,75 s).
export const DURACAO_DO_DESFAZER_MS = 3000;
const PORCENTAGEM_TOTAL = 100;
const QUEM_TROUXE = 'Marina Pavanelli';

// ---- a leitura da planilha de exemplo ----------------------------------------

const SEM_RESPOSTAS = {};

// A planilha de exemplo tem a coluna "Empresa": o telefone da empresa existe.
export const leituraDeExemplo = (id, arquivo = '') =>
  comAsContas({
    id,
    arquivo: arquivo || NOME_DO_ARQUIVO_DE_EXEMPLO,
    valores: 'inteiros',
    temEmpresa: true,
    colunas: copia(COLUNAS),
    perguntas: copia(PERGUNTAS),
    respostas: { ...SEM_RESPOSTAS },
    resumo: { ...RESUMO },
    exemplos: exemplosDe(COLUNAS, SEM_RESPOSTAS),
    problemas: copia(PROBLEMAS).map(problema => ({
      ...problema,
      estado: SITUACAO_DO_PROBLEMA.ABERTO,
    })),
    problemasTotal: PROBLEMAS.length,
  });

// ---- a lista trazida -----------------------------------------------------------

// Na demonstração, 1 de cada 10 pessoas novas já tinha conversado: "Clientes
// 2025.xlsx" (180 novas) fica com 18 que ficam ao desfazer.
const UMA_EM_DEZ = 10;
const ficamNaTrazida = novas => Math.floor(novas / UMA_EM_DEZ);

// Os números da lista que acabou de ser trazida: o que de fato entrou, como o
// andamento do servidor conta (app/services/relacionamentos/trazer/
// andamento.rb). No Conferir a linha consertada não é chamada de "nova" (o
// servidor ainda não sabe se a pessoa já existe na conta): ela só aparece em
// quantas entram. Depois de trazida, ela entrou; e na demonstração quem foi
// consertado é sempre pessoa nova. Por isso `novas` aqui é maior que a do
// Conferir, e a soma fecha com o que o Conferir disse que entrava.
export const contasDaTrazida = leitura => {
  const novas = leitura.resumo.novas + consertadas(leitura);
  return {
    total: leitura.resumo.entram,
    novas,
    completadas: leitura.resumo.completadas,
    ficam: ficamNaTrazida(novas),
  };
};

// As listas que a conta "já trouxe". Em `vazio` não há nenhuma. A última parou
// no meio (#2896): o histórico diz isso e oferece "Tentar de novo".
export const historicoInicial = (agora, estado = 'cheio') =>
  estado === 'vazio'
    ? []
    : [
        {
          id: 'trazida-antiga-1',
          arquivo: 'Clientes de setembro.xlsx',
          quando: agora - 3 * DIA_EM_MS,
          quem: QUEM_TROUXE,
          situacao: SITUACOES_DA_LISTA.PRONTO,
          total: 132,
          novas: 120,
          completadas: 12,
          ficam: 16,
        },
        {
          id: 'trazida-antiga-2',
          arquivo: 'Feira de março.csv',
          quando: agora - 12 * DIA_EM_MS,
          quem: QUEM_TROUXE,
          situacao: SITUACOES_DA_LISTA.DESFEITO,
          total: 48,
          novas: 48,
          completadas: 0,
          ficam: 0,
        },
        {
          id: 'trazida-antiga-3',
          arquivo: 'Contatos de outubro.xlsx',
          quando: agora - 40 * DIA_EM_MS,
          quem: QUEM_TROUXE,
          situacao: SITUACOES_DA_LISTA.PRONTO,
          total: 62,
          novas: 55,
          completadas: 7,
          ficam: 14,
        },
        {
          id: 'trazida-antiga-4',
          arquivo: 'Indicações de agosto.csv',
          quando: agora - 55 * DIA_EM_MS,
          quem: QUEM_TROUXE,
          situacao: SITUACOES_DA_LISTA.FALHOU,
          podeTentar: true,
          total: 80,
          novas: 70,
          completadas: 10,
          ficam: 7,
        },
      ];

export const quemTrouxeNaDemo = () => QUEM_TROUXE;

// De 0 a 100 em DURACAO_DA_TRAZIDA_MS, sempre igual para o mesmo relógio.
export const porcentagemDaTrazida = (inicio, agora) =>
  Math.min(
    PORCENTAGEM_TOTAL,
    Math.max(
      0,
      Math.floor(((agora - inicio) / DURACAO_DA_TRAZIDA_MS) * PORCENTAGEM_TOTAL)
    )
  );

// O desfazer pedido em `inicio` já terminou?
export const desfazerTerminou = (inicio, agora) =>
  agora - inicio >= DURACAO_DO_DESFAZER_MS;
