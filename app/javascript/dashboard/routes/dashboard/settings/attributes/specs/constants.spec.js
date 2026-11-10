import { ATTRIBUTE_TYPES, tiposDoModelo } from '../constants';

// Decisão 16 — o tipo Contato só existe no card: criar e editar o campo usam o
// mesmo filtro de tipos por modelo.
const chaves = modelo => tiposDoModelo(modelo).map(tipo => tipo.key);

describe('tiposDoModelo', () => {
  it('no card, oferece todos os tipos, inclusive Contato', () => {
    expect(chaves(3)).toEqual(ATTRIBUTE_TYPES.map(tipo => tipo.key));
    expect(chaves('card_attribute')).toContain('CONTATO');
  });

  it('fora do card, o tipo Contato não aparece, pelo id ou pelo nome', () => {
    [0, 1, 2, 'conversation_attribute', 'contact_attribute'].forEach(modelo => {
      expect(chaves(modelo)).not.toContain('CONTATO');
      expect(chaves(modelo)).toContain('NUMBER');
    });
  });
});
