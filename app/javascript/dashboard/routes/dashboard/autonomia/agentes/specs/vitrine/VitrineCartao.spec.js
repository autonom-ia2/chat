import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { ferramentaPorId } from '../../vitrine/catalogo';

// #2858 F5 — o cartão da base que a plataforma baixa diz de quando é a cópia ("Atualizado em…"), com o dia que o
// servidor manda; antes da primeira cópia, que os dados chegam logo. A fonte que não é base não mostra nada disso.
const api = vi.hoisted(() => ({ listar: vi.fn() }));
vi.mock('dashboard/api/autonomia/ferramentasProntas', () => ({ default: api }));

withFullI18n('pt_BR');

const montar = async (id, fontes) => {
  vi.resetModules();
  api.listar.mockResolvedValue({ data: { fontes, incluidas: [] } });
  const { useVitrine } = await import('../../vitrine/useVitrine');
  await useVitrine().carregar();
  const { default: VitrineCartao } = await import(
    '../../vitrine/components/VitrineCartao.vue'
  );
  return mount(VitrineCartao, { props: { ferramenta: ferramentaPorId(id) } });
};

describe('VitrineCartao · atualizado em', () => {
  it('shows the day of the copy for a downloaded database', async () => {
    const wrapper = await montar('aeronaves', [
      { chave: 'aeronaves', atualizado_em: '2026-11-11' },
    ]);

    expect(wrapper.find('[data-vitrine-atualizado]').text()).toBe(
      'Atualizado em 11/11/2026'
    );
  });

  it('says the data is on its way before the first copy', async () => {
    const wrapper = await montar('transportadoras', [
      { chave: 'transportadoras', atualizado_em: null },
    ]);

    expect(wrapper.find('[data-vitrine-atualizado]').text()).toBe(
      'Os dados chegam em até 1 dia'
    );
  });

  it('shows nothing of it for a source that is not a database', async () => {
    const wrapper = await montar('cep', [{ chave: 'cep' }]);

    expect(wrapper.find('[data-vitrine-atualizado]').exists()).toBe(false);
  });
});
