import { useContactFilterContext } from '../contactProvider';

// #2138 — os campos internos da WAHA (waha_whatsapp_chat_id/jid/lid) não entram
// nos filtros de contato; os campos de verdade continuam. A lista passa pelo
// getter de verdade (attributes/getContactAttributes), que os esconde.
const state = vi.hoisted(() => ({ contactAttributes: [], features: [] }));

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store.js', async () => {
  const { getters } = await import('dashboard/store/modules/attributes');
  return {
    useMapGetter: nome => {
      if (nome === 'getCurrentAccountId') return { value: 1 };
      // #2084: a chave da conta (o filtro "Este contato é" só com contato_relacao).
      if (nome === 'accounts/isFeatureEnabledonAccount')
        return { value: (_conta, chave) => state.features.includes(chave) };
      if (nome !== 'attributes/getContactAttributes') return { value: [] };
      return {
        get value() {
          return getters.getContactAttributes({
            records: state.contactAttributes,
          });
        },
      };
    },
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
    state.features = [];
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

describe('useContactFilterContext — Este contato é (#2084)', () => {
  const relacao = () =>
    useContactFilterContext().filterTypes.value.find(
      tipo => tipo.attributeKey === 'relacao'
    );

  it('fica fora sem a chave contato_relacao', () => {
    state.features = [];
    expect(relacao()).toBeUndefined();
  });

  it('com a chave, filtra pelas três relações, mandando o nome', () => {
    state.features = ['contato_relacao'];
    expect(relacao().options.map(opcao => opcao.id)).toEqual([
      'interessado',
      'parceiro',
      'nao_e_negocio',
    ]);
  });
});
