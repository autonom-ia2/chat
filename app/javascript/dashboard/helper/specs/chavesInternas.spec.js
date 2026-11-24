import {
  chavesInternasDaConta,
  ehChaveInterna,
  semChavesInternas,
} from '../chavesInternas';

// #2138, #3176 — a lista é a do servidor (app/services/relationships/
// chaves_internas.rb), que chega na resposta da conta (`chaves_internas`).
const CHAVES = [
  'waha_whatsapp_chat_id',
  'waha_whatsapp_jid',
  'waha_whatsapp_lid',
  'autonomia_prospecting_lead_id',
];

describe('chaves internas', () => {
  it('lê a lista da conta; sem conta ou sem lista, nada é interno', () => {
    expect(chavesInternasDaConta({ id: 1, chaves_internas: CHAVES })).toBe(
      CHAVES
    );
    expect(chavesInternasDaConta({ id: 1 })).toEqual([]);
    expect(chavesInternasDaConta(undefined)).toEqual([]);
    expect(chavesInternasDaConta({ chaves_internas: 'waha' })).toEqual([]);
  });

  it('compara a chave inteira, sem prefixo: parecida não é interna', () => {
    expect(ehChaveInterna('waha_whatsapp_jid', CHAVES)).toBe(true);
    expect(ehChaveInterna('autonomia_prospecting_lead_id', CHAVES)).toBe(true);
    expect(ehChaveInterna('waha_whatsapp_outra', CHAVES)).toBe(false);
    expect(ehChaveInterna('autonomia_prospecting_rating', CHAVES)).toBe(false);
    expect(ehChaveInterna('melhor_horario', CHAVES)).toBe(false);
    expect(ehChaveInterna(undefined, CHAVES)).toBe(false);
    expect(ehChaveInterna('waha_whatsapp_jid')).toBe(false);
    expect(ehChaveInterna('waha_whatsapp_jid', null)).toBe(false);
  });

  it('tira só as internas, na mesma ordem, sem mexer nas outras definições', () => {
    const definicoes = [
      { id: 1, attribute_key: 'melhor_horario' },
      { id: 2, attribute_key: 'waha_whatsapp_chat_id' },
      { id: 3, attribute_key: 'waha_whatsapp_jid' },
      { id: 4, attribute_key: 'cpf' },
      { id: 5, attribute_key: 'autonomia_prospecting_lead_id' },
    ];
    const copia = JSON.parse(JSON.stringify(definicoes));

    expect(semChavesInternas(definicoes, CHAVES)).toEqual([
      definicoes[0],
      definicoes[3],
    ]);
    expect(definicoes).toEqual(copia);
    expect(semChavesInternas()).toEqual([]);
  });

  it('sem a lista da conta, nenhuma definição sai', () => {
    const definicoes = [
      { id: 1, attribute_key: 'melhor_horario' },
      { id: 2, attribute_key: 'waha_whatsapp_chat_id' },
    ];
    expect(semChavesInternas(definicoes)).toEqual(definicoes);
  });

  it('aceita a definição em camelCase (attributeKey), como sai do getter', () => {
    const definicoes = [
      { id: 1, attributeKey: 'melhor_horario' },
      { id: 2, attributeKey: 'waha_whatsapp_lid' },
    ];
    expect(semChavesInternas(definicoes, CHAVES)).toEqual([definicoes[0]]);
  });
});
