import { flushPromises, mount } from '@vue/test-utils';
import { ref } from 'vue';
import { withFullI18n } from 'test-i18n';
import VitrineSugestaoDoAgente from '../../vitrine/components/VitrineSugestaoDoAgente.vue';

// #2858 F3 — o cartão "pode ganhar" na página do agente: lê a sugestão que o servidor já tem (nunca espera o modelo),
// mostra UMA ferramenta, "Incluir" usa o caminho da vitrine e "Agora não" grava que ela não volta. Sem o Construtor
// (flag ou chave), nada é pedido. Cópia real em pt_BR.
withFullI18n('pt_BR');

const api = vi.hoisted(() => ({ sugestoes: vi.fn(), dispensar: vi.fn() }));
vi.mock('dashboard/api/autonomia/ferramentasProntas', () => ({
  default: api,
}));
const vitrine = vi.hoisted(() => ({
  carregar: vi.fn(),
  tem: vi.fn(() => false),
  incluir: vi.fn(),
}));
vi.mock('../../vitrine/useVitrine', () => ({ useVitrine: () => vitrine }));
const construtor = vi.hoisted(() => ({ valor: null }));
vi.mock('../../vitrine/useVitrineLigada', () => ({
  useVitrineLigada: () => ({ construtor: construtor.valor }),
}));
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));

const montadas = [];
const montar = async () => {
  const wrapper = mount(VitrineSugestaoDoAgente, {
    props: { agenteId: 7, nome: 'Ana' },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

beforeEach(() => {
  construtor.valor = ref(true);
  api.sugestoes.mockReset().mockResolvedValue({
    data: { ferramentas: ['fipe', 'cep'] },
  });
  api.dispensar.mockReset().mockResolvedValue({});
  vitrine.incluir.mockReset().mockResolvedValue({});
  vitrine.tem.mockReset().mockReturnValue(false);
  alerta.mockReset();
});
afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('VitrineSugestaoDoAgente', () => {
  it('skips an internal-use source even if it was stored as a suggestion', async () => {
    api.sugestoes.mockResolvedValue({
      data: { ferramentas: ['produtos_seguradoras', 'fipe'] },
    });
    const wrapper = await montar();

    expect(wrapper.text()).toContain('Ana pode ganhar: Valor do carro.');
    expect(wrapper.text()).not.toContain('Produtos das seguradoras');
  });

  it('shows one tool from the stored suggestion', async () => {
    const wrapper = await montar();

    expect(api.sugestoes).toHaveBeenCalledWith(7);
    expect(wrapper.findAll('[data-vitrine-sugestao]')).toHaveLength(1);
    expect(wrapper.text()).toContain('Ana pode ganhar: Valor do carro.');
  });

  it('"Add" goes through the showcase with the "Use when" sentence and moves to the next one', async () => {
    const wrapper = await montar();

    await wrapper.find('[data-vitrine-sugestao-incluir]').trigger('click');
    await flushPromises();

    expect(vitrine.incluir).toHaveBeenCalledWith({
      fonte: 'fipe',
      agenteId: 7,
      usarQuando:
        'Use quando o cliente quiser saber quanto vale um carro, moto ou caminhão.',
    });
    expect(alerta).toHaveBeenCalledWith(
      'Pronto! Ana já consegue dizer quanto vale um carro.'
    );
    expect(wrapper.text()).not.toContain('Valor do carro');
  });

  it('"Not now" hides it right away and records it for this agent', async () => {
    const wrapper = await montar();

    await wrapper.find('[data-vitrine-sugestao-dispensar]').trigger('click');
    await flushPromises();

    expect(api.dispensar).toHaveBeenCalledWith(7, 'fipe');
    expect(vitrine.incluir).not.toHaveBeenCalled();
    expect(wrapper.text()).not.toContain('Valor do carro');
  });

  it('a failed "Add" says why and keeps the card', async () => {
    vitrine.incluir.mockRejectedValue(
      Object.assign(new Error('x'), { motivo: 'NOME_EM_USO' })
    );
    const wrapper = await montar();

    await wrapper.find('[data-vitrine-sugestao-incluir]').trigger('click');
    await flushPromises();

    expect(alerta).toHaveBeenCalledWith(
      expect.stringContaining('outra ferramenta com o mesmo nome')
    );
    expect(wrapper.find('[data-vitrine-sugestao]').exists()).toBe(true);
  });

  it('"none fits" or a failed read: no card', async () => {
    api.sugestoes.mockResolvedValue({ data: { ferramentas: [] } });
    expect((await montar()).find('[data-vitrine-sugestao]').exists()).toBe(
      false
    );

    api.sugestoes.mockRejectedValue(new Error('rede'));
    expect((await montar()).find('[data-vitrine-sugestao]').exists()).toBe(
      false
    );
  });

  it('without the Construtor for this person: nothing is asked', async () => {
    construtor.valor = ref(false);
    const wrapper = await montar();

    expect(api.sugestoes).not.toHaveBeenCalled();
    expect(wrapper.find('[data-vitrine-sugestao]').exists()).toBe(false);
  });
});
