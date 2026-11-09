export const ATTRIBUTE_MODELS = [
  { id: 0, key: 'CONVERSATION' },
  { id: 1, key: 'CONTACT' },
  { id: 2, key: 'COMPANY' },
  { id: 3, key: 'CARD' },
];

export const ATTRIBUTE_TYPES = [
  { id: 0, key: 'TEXT' },
  { id: 1, key: 'NUMBER' },
  { id: 4, key: 'LINK' },
  { id: 5, key: 'DATE' },
  { id: 6, key: 'LIST' },
  { id: 7, key: 'CHECKBOX' },
  // Decisão 16 (ex. 11): um contato da conta; só no card (CARD_MODEL_ID).
  { id: 9, key: 'CONTATO', soNoModelo: 3 },
];
