import { computed, ref } from 'vue';
import { useReenvioNaCampanha } from '../reenvio/useReenvioNaCampanha';
import { templateVariables } from '../templateVariables';
import { reenvioNovo } from '../reenvio/reenvio';

const corpo = text => [{ type: 'BODY', text }];
const PRIMEIRO = {
  id: 'm1',
  name: 'renovacao',
  language: 'pt_BR',
  components: corpo('Olá, {{1}}! O seguro vence em {{2}}.'),
};
const LEMBRETE = {
  id: 'm2',
  name: 'lembrete',
  language: 'pt_BR',
  category: 'UTILITY',
  components: corpo('Olá, {{1}}! Ainda quer falar sobre {{2}}?'),
};
const CUPOM = {
  id: 'm3',
  name: 'cupom',
  language: 'pt_BR',
  components: [
    ...corpo('Use o cupom'),
    { type: 'BUTTONS', buttons: [{ type: 'COPY_CODE', text: 'Copiar' }] },
  ],
};

const ponteSemModelos = {
  rotular: variaveis => variaveis,
  ligacoesIniciais: () => ({}),
  gruposDeCampos: computed(() => []),
};

const montar = ({ draft, ponte = ponteSemModelos } = {}) => {
  const rascunho = ref({
    channel: 'whatsapp_official',
    templateId: 'm1',
    bindings: {
      1: { source: 'contact', value: 'first_name', suggested: true },
      2: { source: 'column', value: 'Vencimento' },
    },
    ...draft,
  });
  const templates = computed(() => [PRIMEIRO, LEMBRETE, CUPOM]);
  return useReenvioNaCampanha({
    draft: rascunho,
    ponte,
    templates,
    templateOptions: computed(() =>
      templates.value.map(item => ({ value: item.id, label: item.name }))
    ),
    variables: computed(() => templateVariables(PRIMEIRO)),
    sample: ref({ name: 'Ana Souza', first_name: 'Ana' }),
    columns: computed(() => ['Vencimento']),
    placeholder: ligacao => `[${ligacao.value}]`,
    pedeOferta: template => template.id === 'm3',
    motivoDaOferta: 'has a coupon',
  });
};

describe('useReenvioNaCampanha (#3101, §3.1)', () => {
  it('offers the other templates of the inbox, without the first one', () => {
    const { reenvio } = montar();

    expect(reenvio.value.canal).toBe('whatsapp_official');
    expect(reenvio.value.modelos.map(modelo => modelo.value)).toEqual([
      'm2',
      'm3',
    ]);
    expect(reenvio.value.colunas).toEqual(['Vencimento']);
    expect(reenvio.value.maximoDoTexto).toBe(1000);
  });

  it('brings the binding of the first message only for the variable with the same key and label', () => {
    const { reenvio } = montar();
    const [lembrete] = reenvio.value.modelos;

    // {{1}} tem o mesmo rótulo ("Olá,") nos dois modelos; {{2}} fala de outra coisa.
    expect(lembrete.ligacoes).toEqual({
      1: { source: 'contact', value: 'first_name' },
    });
    expect(lembrete.corpo).toBe('Olá, Ana! Ainda quer falar sobre {{2}}?');
  });

  it('lets the catalog binding of the template win', () => {
    const ponte = {
      ...ponteSemModelos,
      ligacoesIniciais: id =>
        id === 'm2' ? { 1: { source: 'field', value: 'cliente.nome' } } : {},
    };
    const { reenvio } = montar({ ponte });

    expect(reenvio.value.modelos[0].ligacoes[1]).toEqual({
      source: 'field',
      value: 'cliente.nome',
    });
  });

  it('shows the body with the bindings chosen for the second message', () => {
    const { reenvio } = montar({
      draft: {
        reenvio: {
          ...reenvioNovo(),
          modeloId: 'm2',
          ligacoes: {
            1: { source: 'contact', value: 'first_name' },
            2: { source: 'fixed', value: 'o seguro do carro' },
          },
        },
      },
    });

    expect(reenvio.value.modelos[0].corpo).toBe(
      'Olá, Ana! Ainda quer falar sobre o seguro do carro?'
    );
  });

  it('turns off the templates that ask for a coupon, an offer or the catalog, saying why', () => {
    const { reenvio } = montar();
    const cupom = reenvio.value.modelos.find(modelo => modelo.value === 'm3');

    expect(cupom.disabled).toBe(true);
    expect(cupom.label).toBe('cupom · has a coupon');
  });

  it('gives a text box on SMS and nothing on live chat', () => {
    expect(montar({ draft: { channel: 'sms' } }).reenvio.value).toMatchObject({
      canal: 'sms',
      modelos: [],
    });
    expect(montar({ draft: { channel: 'live_chat' } }).reenvio.value).toBe(
      null
    );
  });

  it('builds the second template the way the server keeps it, with the same template params of the first', () => {
    const { modeloParaEnvio } = montar({
      draft: {
        reenvio: {
          ...reenvioNovo(),
          modeloId: 'm2',
          ligacoes: {
            1: { source: 'contact', value: 'first_name', suggested: true },
            2: { source: 'fixed', value: 'o seguro' },
          },
        },
      },
    });

    expect(modeloParaEnvio()).toEqual({
      modelo_id: 'm2',
      template_params: {
        name: 'lembrete',
        namespace: '',
        category: 'UTILITY',
        language: 'pt_BR',
        processed_params: { body: { 1: '', 2: 'o seguro' } },
      },
      ligacoes: {
        1: { source: 'contact', value: 'first_name' },
        2: { source: 'fixed', value: 'o seguro' },
      },
    });
  });

  it('has nothing to send while no template is chosen', () => {
    expect(
      montar({ draft: { reenvio: reenvioNovo() } }).modeloParaEnvio()
    ).toBe(null);
  });
});
