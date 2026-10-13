import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import CampanhasParadas from '../components/CampanhasParadas.vue';
import EtapaObjetivo from '../components/criar/EtapaObjetivo.vue';
import ModeloUsos from '../components/ModeloUsos.vue';
import FranquiaDoMes from '../components/FranquiaDoMes.vue';
import PonteSemModelo from '../ponte/PonteSemModelo.vue';
import EscolherArquivo from '../components/criar/EscolherArquivo.vue';

const api = vi.hoisted(() => ({
  retomarCampanha: vi.fn(),
  obterFranquia: vi.fn(),
  custoPorEnvio: vi.fn(),
}));
vi.mock('../api/modelosWhatsapp', () => ({ default: api }));
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en } });

// `flags`: as flags ligadas na conta (o piloto da IA é whatsapp_templates_ai).
const loja = (papel, flags = []) =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({
        id: 1,
        accounts: [{ id: 1, role: papel, permissions: [papel] }],
      }),
      'accounts/isFeatureEnabledonAccount': () => (_conta, flag) =>
        flags.includes(flag),
    },
  });

const montar = (
  componente,
  { props = {}, papel = 'administrator', flags = [] } = {}
) =>
  mount(componente, {
    props,
    global: {
      plugins: [i18n(), loja(papel, flags)],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });

const PARADA = {
  id: 4,
  pausaId: 31,
  nome: 'Outubro',
  modeloId: '1001',
  modeloNome: 'Boas-vindas',
  motivo: 'modelo_pausado',
  podeRetomar: true,
};

beforeEach(() => {
  Object.values(api).forEach(fn => fn.mockReset());
  alerta.mockClear();
});

describe('CampanhasParadas', () => {
  it('resumes a paused campaign and tells the page to reload', async () => {
    api.retomarCampanha.mockResolvedValue({});
    const wrapper = montar(CampanhasParadas, {
      props: { campanhas: [PARADA] },
    });

    expect(wrapper.text()).toContain('Boas-vindas');
    await wrapper.find('[data-retomar]').trigger('click');
    await flushPromises();

    expect(api.retomarCampanha).toHaveBeenCalledWith(31);
    expect(wrapper.emitted('retomada')).toHaveLength(1);
  });

  it('says why when the campaign cannot be resumed', async () => {
    api.retomarCampanha.mockRejectedValue({
      codigo: 'campaign_journey.pause_not_resumable',
    });
    const wrapper = montar(CampanhasParadas, {
      props: { campanhas: [PARADA] },
    });

    await wrapper.find('[data-retomar]').trigger('click');
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith(
      en.MODELOS_WHATSAPP.PARADAS.NAO_RETOMOU
    );
    expect(wrapper.emitted('retomada')).toBeUndefined();
  });

  it('keeps "Resume" off and points to the template until it is approved again', async () => {
    const wrapper = montar(CampanhasParadas, {
      props: { campanhas: [{ ...PARADA, podeRetomar: false }] },
    });

    expect(wrapper.find('[data-retomar]').attributes('disabled')).toBeDefined();
    // Pausado não tem o que corrigir: é esperar o WhatsApp liberar.
    expect(wrapper.find('[data-corrija-primeiro]').text()).toContain(
      en.MODELOS_WHATSAPP.PARADAS.AGUARDE_LIBERAR
    );
    await wrapper.find('[data-retomar]').trigger('click');
    expect(api.retomarCampanha).not.toHaveBeenCalled();
  });

  it('asks to fix only a rejected template', () => {
    const wrapper = montar(CampanhasParadas, {
      props: {
        campanhas: [
          { ...PARADA, motivo: 'modelo_recusado', podeRetomar: false },
        ],
      },
    });
    expect(wrapper.find('[data-corrija-primeiro]').text()).toContain(
      en.MODELOS_WHATSAPP.PARADAS.CORRIJA_PRIMEIRO
    );
  });

  it('hides "Resume" from who cannot manage campaigns', () => {
    const wrapper = montar(CampanhasParadas, {
      props: { campanhas: [PARADA] },
      papel: 'agent',
    });
    expect(wrapper.find('[data-retomar]').exists()).toBe(false);
  });
});

describe('ModeloUsos', () => {
  it('shows hidden usage only as a notice, without a name', () => {
    const wrapper = montar(ModeloUsos, {
      props: {
        usos: [{ tipo: 'oculto', nome: '', agendado: true, rota: null }],
      },
    });
    expect(wrapper.text()).toContain(en.MODELOS_WHATSAPP.USOS.OCULTO);
  });
});

describe('EtapaObjetivo', () => {
  it('shows "Criar com IA" only with the AI pilot flag (#1333, Refs #1450)', () => {
    expect(
      montar(EtapaObjetivo, { flags: ['whatsapp_templates_ai'] })
        .find('[data-criar-com-ia-entrada]')
        .exists()
    ).toBe(true);
    expect(
      montar(EtapaObjetivo).find('[data-criar-com-ia-entrada]').exists()
    ).toBe(false);
  });

  it('has no format without backend (catalog, form)', () => {
    const wrapper = montar(EtapaObjetivo);
    expect(wrapper.find('[data-formato="catalogo"]').exists()).toBe(false);
    expect(wrapper.find('[data-formato="formulario"]').exists()).toBe(false);
    expect(wrapper.find('[data-formato="carrossel"]').exists()).toBe(true);
  });

  it('says in plain words that the other formats do not go in campaigns yet', () => {
    const wrapper = montar(EtapaObjetivo);
    const avisos = wrapper.findAll('[data-nao-vai-em-campanha]');
    expect(avisos.map(aviso => aviso.text())).toEqual(
      Array(3).fill(en.MODELOS_WHATSAPP.OBJETIVO.NAO_VAI_EM_CAMPANHA)
    );
  });
});

describe('EscolherArquivo', () => {
  const escolher = async (wrapper, arquivo) => {
    const input = wrapper.find('input[type="file"]');
    Object.defineProperty(input.element, 'files', {
      value: [arquivo],
      configurable: true,
    });
    await input.trigger('change');
  };

  it('recusa arquivo grande ou do tipo errado logo ao escolher', async () => {
    const wrapper = montar(EscolherArquivo, {
      props: { aceita: 'image/jpeg,image/png' },
    });
    const grande = new File(['x'], 'foto.jpg', { type: 'image/jpeg' });
    Object.defineProperty(grande, 'size', { value: 6 * 1024 * 1024 });
    await escolher(wrapper, grande);
    expect(wrapper.find('[data-arquivo-erro]').text()).toBe(
      en.MODELOS_WHATSAPP.EXTRAS.ARQUIVO_GRANDE.foto
    );
    await escolher(
      wrapper,
      new File(['x'], 'nota.txt', { type: 'text/plain' })
    );
    expect(wrapper.find('[data-arquivo-erro]').text()).toBe(
      en.MODELOS_WHATSAPP.EXTRAS.ARQUIVO_ERRADO.foto
    );
    expect(wrapper.emitted('escolhido')).toBeUndefined();
    await escolher(wrapper, new File(['x'], 'ok.png', { type: 'image/png' }));
    expect(wrapper.emitted('escolhido')).toHaveLength(1);
    expect(wrapper.find('[data-arquivo-erro]').exists()).toBe(false);
  });
});

describe('PonteSemModelo', () => {
  it('com modelos que não vão, diz por quê e oferece criar e corrigir', async () => {
    const wrapper = montar(PonteSemModelo, {
      props: { temModelos: true, paraCorrigir: { id: '9', nome: 'Boleto' } },
    });
    expect(wrapper.text()).toContain(
      en.MODELOS_WHATSAPP.PONTE.SEM_MODELO_LIBERADO
    );
    expect(wrapper.find('[data-criar-modelo]').exists()).toBe(true);
    await wrapper.find('[data-corrigir-modelo]').trigger('click');
    expect(wrapper.emitted('corrigir')).toEqual([['9']]);
  });
});

describe('FranquiaDoMes', () => {
  it('shows the free replies of each number and who went over', async () => {
    api.obterFranquia.mockResolvedValue({
      limite: 1000,
      numeros: [
        { id: 8, nome: 'Vendas', usadas: 230 },
        { id: 9, nome: 'Filial', usadas: 1001 },
      ],
    });
    api.custoPorEnvio.mockResolvedValue({ valor: 0.035, moeda: 'BRL' });
    const wrapper = montar(FranquiaDoMes);
    await flushPromises();

    expect(api.custoPorEnvio).toHaveBeenCalledWith('resposta');
    expect(wrapper.find('[data-franquia-numero="8"]').text()).toContain(
      '230 of 1,000'
    );
    expect(wrapper.find('[data-franquia-numero="9"]').text()).toContain(
      'Over the 1,000 free ones'
    );
  });

  it('does not show without data', async () => {
    api.obterFranquia.mockRejectedValue(new Error('401'));
    api.custoPorEnvio.mockResolvedValue(null);
    const wrapper = montar(FranquiaDoMes);
    await flushPromises();
    expect(wrapper.find('[data-franquia]').exists()).toBe(false);
  });
});
