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

// O id de cada modelo, como a API devolve o nome (`card_attribute`).
const ID_DO_MODELO = {
  conversation_attribute: 0,
  contact_attribute: 1,
  company_attribute: 2,
  card_attribute: 3,
};

// Os tipos que o modelo aceita (pelo id ou pelo nome): o tipo com `soNoModelo`
// só aparece no modelo dele. Usado ao criar e ao editar o campo.
export const tiposDoModelo = modelo => {
  const id = typeof modelo === 'string' ? ID_DO_MODELO[modelo] : modelo;
  return ATTRIBUTE_TYPES.filter(
    item => item.soNoModelo === undefined || item.soNoModelo === id
  );
};
