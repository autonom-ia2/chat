import { mount, flushPromises } from '@vue/test-utils';
import VozDoInstagram from '../VozDoInstagram.vue';
import { carregarOnda } from '../../audio/ondaDoAudio';

const visivel = vi.hoisted(() => ({ callback: null }));
vi.mock('@vueuse/core', async original => ({
  ...(await original()),
  useIntersectionObserver: (_alvo, callback) => {
    visivel.callback = callback;
    return { stop: vi.fn() };
  },
}));
vi.mock('../../audio/ondaDoAudio', async original => ({
  ...(await original()),
  carregarOnda: vi.fn(),
}));

const ARQUIVO = 'https://app.exemplo.com/rails/active_storage/voz.ogg';

const montar = (anexo = {}) =>
  mount(VozDoInstagram, {
    props: {
      anexo: { id: 41, dataUrl: ARQUIVO, ...anexo },
      cantos: {},
    },
  });

const alturas = wrapper =>
  wrapper
    .findAll('[data-barra-da-voz]')
    .map(barra => barra.classes().find(classe => classe.startsWith('h-[')));

const aparecerNaTela = async () => {
  visivel.callback([{ isIntersecting: true }]);
  await flushPromises();
};

// #2113: a onda da voz do Direct é a do próprio arquivo; sem ela, as barras de reserva.
describe('Onda da voz do Instagram', () => {
  beforeEach(() => {
    carregarOnda.mockReset();
    visivel.callback = null;
  });

  it('só baixa a onda quando o balão aparece na tela', async () => {
    carregarOnda.mockResolvedValue(null);
    montar();
    await flushPromises();
    expect(carregarOnda).not.toHaveBeenCalled();

    await aparecerNaTela();

    expect(carregarOnda).toHaveBeenCalledTimes(1);
    expect(carregarOnda.mock.calls[0][0]).toContain(
      'rails/active_storage/voz.ogg'
    );
    // A onda fica guardada pelo endereço sem o carimbo de tempo: volta à conversa sem baixar de novo.
    expect(carregarOnda.mock.calls[0][1].chave).toBe(ARQUIVO);
  });

  it('desenha a onda calculada do arquivo nas 32 barras do Direct', async () => {
    carregarOnda.mockResolvedValue({
      barras: Array.from({ length: 48 }, (_, i) => (i < 24 ? 0 : 11)),
      duracao: 7,
    });
    const wrapper = montar();

    await aparecerNaTela();

    const barras = alturas(wrapper);
    expect(barras).toHaveLength(32);
    expect(barras[0]).toBe('h-[3px]');
    expect(barras[31]).toBe('h-[26px]');
    expect(wrapper.text()).toContain('0:07');
  });

  it('se o arquivo não puder ser lido, ficam as barras de reserva do anexo', async () => {
    const reserva = alturas(montar());
    carregarOnda.mockResolvedValue(null);
    const wrapper = montar();

    await aparecerNaTela();

    expect(alturas(wrapper)).toHaveLength(32);
    expect(alturas(wrapper)).toEqual(reserva);
  });

  it('sem endereço válido não tenta baixar e fica na reserva', async () => {
    const wrapper = montar({ dataUrl: '' });

    await aparecerNaTela();

    expect(carregarOnda).not.toHaveBeenCalled();
    expect(alturas(wrapper)).toHaveLength(32);
  });
});
