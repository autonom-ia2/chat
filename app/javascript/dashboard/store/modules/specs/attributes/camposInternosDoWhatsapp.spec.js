import { getters, mutations } from '../../attributes';
import types from '../../../mutation-types';

// #2138 — os campos internos da WAHA (waha_whatsapp_chat_id/jid/lid) não saem de
// nenhum getter de definições; os registros guardados continuam inteiros.
const definicao = (id, chave, modelo = 'contact_attribute') => ({
  id,
  attribute_key: chave,
  attribute_display_name: chave,
  attribute_display_type: 'text',
  attribute_model: modelo,
});
const REGISTROS = [
  definicao(1, 'melhor_horario'),
  definicao(2, 'waha_whatsapp_chat_id'),
  definicao(3, 'waha_whatsapp_jid'),
  definicao(4, 'waha_whatsapp_lid'),
  definicao(5, 'canal', 'conversation_attribute'),
  definicao(6, 'porte', 'company_attribute'),
  definicao(7, 'valor', 'card_attribute'),
];
const chaves = lista =>
  lista.map(item => item.attribute_key ?? item.attributeKey);

describe('attributes getters — campos internos da WAHA', () => {
  const state = { records: REGISTROS };

  it('getAttributes devolve tudo menos os internos', () => {
    expect(chaves(getters.getAttributes(state))).toEqual([
      'melhor_horario',
      'canal',
      'porte',
      'valor',
    ]);
  });

  it('getAttributesByModel("contact_attribute") não traz os internos', () => {
    expect(
      chaves(getters.getAttributesByModel(state)('contact_attribute'))
    ).toEqual(['melhor_horario']);
  });

  it('getContactAttributes (camelCase) não traz os internos', () => {
    expect(chaves(getters.getContactAttributes(state))).toEqual([
      'melhor_horario',
    ]);
  });

  it('os outros modelos ficam como estão', () => {
    expect(chaves(getters.getConversationAttributes(state))).toEqual(['canal']);
    expect(chaves(getters.getCompanyAttributes(state))).toEqual(['porte']);
    expect(chaves(getters.getCardAttributes(state))).toEqual(['valor']);
  });

  it('o estado guarda as definições inteiras (nada apagado)', () => {
    const guardado = { records: [] };
    mutations[types.SET_CUSTOM_ATTRIBUTE](guardado, REGISTROS);
    expect(guardado.records).toHaveLength(REGISTROS.length);
    expect(REGISTROS).toHaveLength(7);
  });
});
