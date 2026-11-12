// #2895 — o canal e a situação que o servidor manda, na chave de tradução que a
// tela tem. O que a tela não conhece cai num rótulo neutro ("Outro canal",
// "Outra situação"): a chave crua nunca aparece e nada quebra quando o servidor
// ganha um valor novo.
export const CANAIS = ['whatsapp', 'email', 'instagram', 'site'];
export const SITUACOES_DE_CONVERSA = [
  'aberta',
  'pendente',
  'resolvida',
  'adiada',
];
// Os estados do card no CRM com as palavras do servidor
// (Relacionamentos::Ficha::Cards::SITUACOES). Card arquivado não vem na ficha.
export const SITUACOES_DE_CARD = [
  'aberto',
  'ganho',
  'perdido',
  'resolvido',
  'cancelado',
];

const CANAL_NEUTRO = 'outro';
const SITUACAO_NEUTRA = 'outra';

const conhecidoOu = (conhecidos, neutro) => valor =>
  conhecidos.includes(valor) ? valor : neutro;

export const canalConhecido = conhecidoOu(CANAIS, CANAL_NEUTRO);
export const situacaoDeConversaConhecida = conhecidoOu(
  SITUACOES_DE_CONVERSA,
  SITUACAO_NEUTRA
);
export const situacaoDeCardConhecida = conhecidoOu(
  SITUACOES_DE_CARD,
  SITUACAO_NEUTRA
);
