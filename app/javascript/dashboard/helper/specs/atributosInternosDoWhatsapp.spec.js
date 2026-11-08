import {
  ATRIBUTOS_INTERNOS_DO_WHATSAPP,
  ehAtributoInternoDoWhatsapp,
  semAtributosInternosDoWhatsapp,
} from '../atributosInternosDoWhatsapp';

// #2138 — as chaves são as de app/services/waha/contact_chat_id.rb.
describe('atributos internos do WhatsApp', () => {
  it('são as três chaves da WAHA, e só elas', () => {
    expect(ATRIBUTOS_INTERNOS_DO_WHATSAPP).toEqual([
      'waha_whatsapp_chat_id',
      'waha_whatsapp_jid',
      'waha_whatsapp_lid',
    ]);
    expect(Object.isFrozen(ATRIBUTOS_INTERNOS_DO_WHATSAPP)).toBe(true);
  });

  it('compara a chave inteira, sem prefixo: parecida não é interna', () => {
    expect(ehAtributoInternoDoWhatsapp('waha_whatsapp_jid')).toBe(true);
    expect(ehAtributoInternoDoWhatsapp('waha_whatsapp_outra')).toBe(false);
    expect(ehAtributoInternoDoWhatsapp('melhor_horario')).toBe(false);
    expect(ehAtributoInternoDoWhatsapp(undefined)).toBe(false);
  });

  it('tira só as internas, na mesma ordem, sem mexer nas outras definições', () => {
    const definicoes = [
      { id: 1, attribute_key: 'melhor_horario' },
      { id: 2, attribute_key: 'waha_whatsapp_chat_id' },
      { id: 3, attribute_key: 'waha_whatsapp_jid' },
      { id: 4, attribute_key: 'cpf' },
      { id: 5, attribute_key: 'waha_whatsapp_lid' },
    ];
    const copia = JSON.parse(JSON.stringify(definicoes));

    expect(semAtributosInternosDoWhatsapp(definicoes)).toEqual([
      definicoes[0],
      definicoes[3],
    ]);
    expect(definicoes).toEqual(copia);
    expect(semAtributosInternosDoWhatsapp()).toEqual([]);
  });

  it('aceita a definição em camelCase (attributeKey), como sai do getter', () => {
    const definicoes = [
      { id: 1, attributeKey: 'melhor_horario' },
      { id: 2, attributeKey: 'waha_whatsapp_lid' },
    ];
    expect(semAtributosInternosDoWhatsapp(definicoes)).toEqual([definicoes[0]]);
  });
});
