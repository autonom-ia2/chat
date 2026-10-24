import { useContactFilterContext } from '../contactProvider';

// #2138 — os campos internos da WAHA (waha_whatsapp_chat_id/jid/lid) não entram
// nos filtros de contato; os campos de verdade continuam. A lista passa pelo
// getter de verdade (attributes/getContactAttributes), que os esconde.
const state = vi.hoisted(() => ({ contactAttributes: [] }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store.js', async () => {
  const { getters } = await import('dashboard/store/modules/attributes');
  return {
    useMapGetter: nome =>
      nome === 'attributes/getContactAttributes'
        ? {
            get value() {
              return getters.getContactAttributes({
                records: state.contactAttributes,
              });
            },
          }
        : { value: [] },
  };
});
vi.mock('dashboard/composables/useNomeDaEtiqueta', () => ({
  useNomeDaEtiqueta: () => ({ nomeDe: nome => nome }),
}));

const definicao = chave => ({
  attribute_key: chave,
  attribute_display_name: chave,
  attribute_display_type: 'text',
  attribute_model: 'contact_attribute',
});

describe('useContactFilterContext — campos internos da WAHA', () => {
  beforeEach(() => {
    state.contactAttributes = [
      definicao('melhor_horario'),
      definicao('waha_whatsapp_chat_id'),
      definicao('waha_whatsapp_jid'),
      definicao('waha_whatsapp_lid'),
    ];
  });

  it('ficam fora dos filtros; o campo de verdade entra', () => {
    const chaves = useContactFilterContext().filterTypes.value.map(
      tipo => tipo.attributeKey
    );
    expect(chaves).toContain('melhor_horario');
    expect(chaves.filter(chave => chave.startsWith('waha_'))).toEqual([]);
  });

  it('também fora da lista agrupada do seletor de campos', () => {
    const texto = JSON.stringify(
      useContactFilterContext().attributeFilterTypes.value
    );
    expect(texto).toContain('melhor_horario');
    expect(texto).not.toContain('waha_whatsapp');
  });
});
