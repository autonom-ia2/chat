// #2894 — dados inventados das ações em grupo da lista (funis, etapas e
// etiquetas). Só é carregado no ambiente de desenvolvimento
// (fonte/acoesDaListaFonte.js, `import.meta.env.DEV`).
export const FUNIS = [
  {
    id: 'vendas',
    nome: 'Vendas',
    etapas: [
      { id: 'primeira-conversa', nome: 'Primeira conversa' },
      { id: 'combinando', nome: 'Combinando' },
      { id: 'fechando', nome: 'Fechando' },
    ],
  },
  {
    id: 'depois-da-compra',
    nome: 'Depois da compra',
    etapas: [
      { id: 'boas-vindas', nome: 'Boas-vindas' },
      { id: 'acompanhando', nome: 'Acompanhando' },
    ],
  },
];

export const ETIQUETAS = [
  'clientes-2025',
  'indicacao',
  'feira',
  'site',
  'evento',
];

// A cada 9 pessoas, uma já tem card no funil: deixa o aviso "ficou de fora"
// aparecer sempre igual nas capturas de tela.
const DE_QUANTAS_EM_QUANTAS_JA_TEM_CARD = 9;

export const MOTIVOS_DO_CARD = { JA_TEM_CARD: 'ja_tem_card' };

export const motivoDeFicarSemCard = pessoa =>
  pessoa.id % DE_QUANTAS_EM_QUANTAS_JA_TEM_CARD === 0
    ? MOTIVOS_DO_CARD.JA_TEM_CARD
    : null;
