// #2897 — os tipos de seguro que a tela conhece, com o ícone e a chave do nome
// no catálogo. Tipo desconhecido cai em "Outro".
export const TIPOS_DE_SEGURO = [
  'auto',
  'residencial',
  'vida',
  'empresarial',
  'outro',
];

const ICONES = {
  auto: 'i-lucide-car',
  residencial: 'i-lucide-house',
  vida: 'i-lucide-heart-pulse',
  empresarial: 'i-lucide-building-2',
  outro: 'i-lucide-shield',
};

const conhecido = tipo => (TIPOS_DE_SEGURO.includes(tipo) ? tipo : 'outro');

export const iconeDoTipo = tipo => ICONES[conhecido(tipo)];

export const chaveDoTipo = tipo =>
  `RELACIONAMENTOS_CARTEIRA.TIPOS.${conhecido(tipo).toUpperCase()}`;
