import { mount, flushPromises } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createStore } from 'vuex';
import en from 'dashboard/i18n/locale/en/modelosWhatsapp.json';
import CampanhasParadas from '../components/CampanhasParadas.vue';
import EtapaObjetivo from '../components/criar/EtapaObjetivo.vue';
import ModeloUsos from '../components/ModeloUsos.vue';
import FranquiaDoMes from '../components/FranquiaDoMes.vue';

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

const loja = papel =>
  createStore({
    getters: {
      getCurrentAccountId: () => 1,
      getCurrentUser: () => ({
        id: 1,
        accounts: [{ id: 1, role: papel, permissions: [papel] }],
      }),
    },
  });

const montar = (componente, { props = {}, papel = 'administrator' } = {}) =>
  mount(componente, {
    props,
    global: {
      plugins: [i18n(), loja(papel)],
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
    expect(wrapper.find('[data-corrija-primeiro]').text()).toContain(
      en.MODELOS_WHATSAPP.PARADAS.CORRIJA_PRIMEIRO
    );
    await wrapper.find('[data-retomar]').trigger('click');
    expect(api.retomarCampanha).not.toHaveBeenCalled();
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
  it('has no AI entry and no format without backend (catalog, form)', () => {
    const wrapper = montar(EtapaObjetivo);
    expect(wrapper.find('[data-criar-com-ia-entrada]').exists()).toBe(false);
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
