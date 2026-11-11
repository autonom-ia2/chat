// #2894 — a planilha fictícia de "Trazer minha lista" e as listas que já foram
// trazidas. Só é carregada no ambiente de desenvolvimento (fonte/trazerFonte.js,
// `import.meta.env.DEV`); em produção o arquivo nem entra no pacote.
//
// Tudo é inventado e sempre igual (nomes com sobrenome que não existe, como em
// demo/base.js): 200 pessoas (180 novas, 15 que já estavam na
// conta e 5 linhas que precisam da pessoa). Telefones no bloco fictício
// +55 11 9XXXX-00NN e e-mails @exemplo.com.br. Aqui ficam também as funções
// puras que "gravam" na leitura: cada uma devolve uma leitura nova.
import { DIA_EM_MS } from '../fonte/grupos';
import { DESTINOS } from '../trazer/destinos';
import { SITUACAO_DO_PROBLEMA } from '../trazer/contagem';
import { SITUACOES_DA_LISTA } from '../trazer/prazo';

export const DURACAO_DA_TRAZIDA_MS = 6000;
const PORCENTAGEM_TOTAL = 100;
const NOME_DO_ARQUIVO_DE_EXEMPLO = 'Planilha de exemplo.xlsx';
const QUEM_TROUXE = 'Marina Dornelaz';

const RESUMO = { total: 200, novas: 180, completadas: 15, comProblema: 5 };

const COLUNAS = [
  { nome: 'Nome', destino: DESTINOS.NOME },
  { nome: 'Cel', destino: DESTINOS.TELEFONE },
  { nome: 'Fone 2', destino: DESTINOS.TELEFONE, duvidosa: true },
  { nome: 'E-mail', destino: DESTINOS.EMAIL },
  { nome: 'Empresa', destino: DESTINOS.EMPRESA },
  { nome: 'Cidade', destino: DESTINOS.CIDADE },
  { nome: 'Situação', destino: DESTINOS.INFORMACAO },
  { nome: 'Aniversário', destino: DESTINOS.INFORMACAO },
];

const PERGUNTAS = [{ id: 'clientes' }, { id: 'telefone', coluna: 'Fone 2' }];

const EXEMPLOS = [
  {
    nome: 'Marina Esteveira',
    telefone: '+55 11 94271-0003',
    email: 'marina.esteveira@exemplo.com.br',
    empresa: 'Casa Aurora',
    clienteNaPlanilha: true,
  },
  {
    nome: 'Otávio Lourenzatto',
    telefone: '+55 11 96538-0007',
    email: 'otavio.lourenzatto@exemplo.com.br',
    empresa: '',
    clienteNaPlanilha: false,
  },
  {
    nome: 'Sofia Mendonzela',
    telefone: '+55 11 93816-0011',
    email: 'sofia.mendonzela@exemplo.com.br',
    empresa: 'Estúdio Vila Nova',
    clienteNaPlanilha: true,
  },
];

// Os 5 problemas: telefone com dígito faltando, e-mail sem "@", linha sem nome,
// a mesma pessoa duas vezes e linha sem telefone nem e-mail.
const PROBLEMAS = [
  {
    linha: 14,
    tipo: 'telefone',
    nome: 'Tadeu Imbirussu',
    valor: '+55 11 9738-0014',
  },
  {
    linha: 37,
    tipo: 'email',
    nome: 'Rita Carvalhedo',
    valor: 'rita.carvalhedo.exemplo.com.br',
  },
  {
    linha: 62,
    tipo: 'nome',
    nome: '',
    valor: '',
    contato: '+55 11 95412-0062',
  },
  {
    linha: 143,
    tipo: 'duplicada',
    nome: 'Paulo Hortêncio',
    valor: 'Paulo Hortêncio',
    outraLinha: 88,
    duplicadas: [
      {
        linha: 88,
        telefone: '+55 11 94410-0088',
        email: 'paulo.hortencio@exemplo.com.br',
      },
      { linha: 143, telefone: '+55 11 94410-0143', email: '' },
    ],
  },
  { linha: 171, tipo: 'sem_contato', nome: 'Helena Ourivesco', valor: '' },
];

const DESTINO_DO_TELEFONE = {
  da_pessoa: DESTINOS.TELEFONE,
  da_empresa: DESTINOS.TELEFONE_DA_EMPRESA,
  nao_usar: DESTINOS.NAO_GUARDAR,
};

export const leituraDeExemplo = (id, arquivo = '') => ({
  id,
  arquivo: arquivo || NOME_DO_ARQUIVO_DE_EXEMPLO,
  colunas: COLUNAS.map(coluna => ({ ...coluna })),
  perguntas: PERGUNTAS.map(pergunta => ({ ...pergunta })),
  resumo: { ...RESUMO },
  exemplos: EXEMPLOS.map(exemplo => ({ ...exemplo, cliente: false })),
  problemas: PROBLEMAS.map(problema => ({
    ...problema,
    estado: SITUACAO_DO_PROBLEMA.ABERTO,
  })),
});

const clienteDoExemplo = (exemplo, { clientes }) => {
  if (clientes === 'sim_todas') return true;
  if (clientes === 'algumas') return exemplo.clienteNaPlanilha;
  return false;
};

const colunaComResposta = (coluna, perguntas, respostas) => {
  const doTelefone = perguntas.find(
    pergunta => pergunta.id === 'telefone' && pergunta.coluna === coluna.nome
  );
  if (doTelefone && DESTINO_DO_TELEFONE[respostas.telefone]) {
    return {
      ...coluna,
      destino: DESTINO_DO_TELEFONE[respostas.telefone],
      duvidosa: false,
    };
  }
  if (
    respostas.clientes === 'algumas' &&
    coluna.nome === respostas.colunaCliente
  ) {
    return { ...coluna, destino: DESTINOS.CLIENTE };
  }
  return coluna;
};

export const aplicarRespostas = (leitura, respostas) => ({
  ...leitura,
  respostas: { ...respostas },
  colunas: leitura.colunas.map(coluna =>
    colunaComResposta(coluna, leitura.perguntas, respostas)
  ),
  exemplos: leitura.exemplos.map(exemplo => ({
    ...exemplo,
    cliente: clienteDoExemplo(exemplo, respostas),
  })),
});

const problemaComSituacao = (leitura, linha, mudanca) => ({
  ...leitura,
  problemas: leitura.problemas.map(problema =>
    problema.linha === linha ? { ...problema, ...mudanca } : problema
  ),
});

export const aplicarConserto = (leitura, linha, valor) =>
  problemaComSituacao(leitura, linha, {
    estado: SITUACAO_DO_PROBLEMA.GUARDADO,
    corrigido: valor,
  });

export const aplicarDeixarDeFora = (leitura, linha) =>
  problemaComSituacao(leitura, linha, {
    estado: SITUACAO_DO_PROBLEMA.DEIXADO,
  });

// "Voltar atrás": a linha volta a ser problema aberto, sem o valor que a pessoa
// tinha posto.
export const aplicarReabrir = (leitura, linha) => ({
  ...leitura,
  problemas: leitura.problemas.map(problema => {
    if (problema.linha !== linha) return problema;
    const { corrigido, ...resto } = problema;
    return { ...resto, estado: SITUACAO_DO_PROBLEMA.ABERTO };
  }),
});

export const aplicarDestino = (leitura, coluna, destino) => ({
  ...leitura,
  colunas: leitura.colunas.map(item =>
    item.nome === coluna ? { ...item, destino } : item
  ),
});

// As listas que a conta "já trouxe". Em `vazio` não há nenhuma.
export const historicoInicial = (agora, estado = 'cheio') =>
  estado === 'vazio'
    ? []
    : [
        {
          id: 'trazida-antiga-1',
          arquivo: 'Clientes 2025.xlsx',
          quando: agora - 3 * DIA_EM_MS,
          quem: QUEM_TROUXE,
          situacao: SITUACOES_DA_LISTA.PRONTO,
          total: 195,
          novas: 180,
          completadas: 15,
          receberamCampanha: 3,
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
          receberamCampanha: 0,
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
