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

// #3062 — com a cor, como a conta guarda (o pontinho ao lado do nome).
export const ETIQUETAS = [
  { nome: 'clientes-2025', cor: '#2F7D5B' },
  { nome: 'evento', cor: '#B45309' },
  { nome: 'feira', cor: '#1F6FEB' },
  { nome: 'indicação', cor: '#8E44AD' },
  { nome: 'site', cor: '#0F766E' },
];

// A cada 9 pessoas, uma já tem card no funil: deixa o aviso "ficou de fora"
// aparecer sempre igual nas capturas de tela.
const DE_QUANTAS_EM_QUANTAS_JA_TEM_CARD = 9;

export const MOTIVOS_DO_CARD = { JA_TEM_CARD: 'ja_tem_card' };

export const motivoDeFicarSemCard = pessoa =>
  pessoa.id % DE_QUANTAS_EM_QUANTAS_JA_TEM_CARD === 0
    ? MOTIVOS_DO_CARD.JA_TEM_CARD
    : null;

// #3075 — as empresas que a escolha da gaveta acha na demonstração.
export const EMPRESAS_DA_BUSCA = [
  { id: 1, nome: 'Padaria Bom Dia' },
  { id: 2, nome: 'Oficina do Bruno' },
  { id: 3, nome: 'Fontanela Transportes' },
  { id: 4, nome: 'Quintanilha Móveis' },
];

// #3078 — "Apagar" das empresas marcadas: a lista da demonstração deixa de
// mostrá-las (demo/base.js), como o servidor faz com a empresa pequena.
export { apagarEmpresaDaDemo } from './base';
