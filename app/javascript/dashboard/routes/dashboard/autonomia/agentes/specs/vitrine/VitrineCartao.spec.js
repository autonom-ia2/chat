import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { ferramentaPorId } from '../../vitrine/catalogo';

// #2858 F5 — o cartão da base que a plataforma baixa diz de quando é a cópia ("Atualizado em…"), com o dia que o
// servidor manda; antes da primeira cópia, que os dados chegam logo, ou "em preparação" se ela já falhou. A fonte que não é base não mostra nada disso.
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

  it('says it is in preparation when the first copy already failed', async () => {
    const wrapper = await montar('geracao_solar', [
      { chave: 'geracao_solar', atualizado_em: null, em_preparacao: true },
    ]);

    expect(wrapper.find('[data-vitrine-atualizado]').text()).toBe(
      'Em preparação'
    );
  });

  it('keeps the day of the copy even if a later round failed', async () => {
    const wrapper = await montar('aeronaves', [
      { chave: 'aeronaves', atualizado_em: '2026-11-11', em_preparacao: false },
    ]);

    expect(wrapper.find('[data-vitrine-atualizado]').text()).toBe(
      'Atualizado em 11/11/2026'
    );
  });

  it('shows nothing of it for a source that is not a database', async () => {
    const wrapper = await montar('cep', [{ chave: 'cep' }]);

    expect(wrapper.find('[data-vitrine-atualizado]').exists()).toBe(false);
  });
});

// #2946 — quantas perguntas o card Premium responde vem do servidor (`premium.consultas`): a conta muda quando a
// BigDataCorp desliga uma consulta, e a tela acompanha sem número próprio. Com uma só, o cartão não ganha o selo.
describe('VitrineCartao · tipos de pergunta do Premium', () => {
  const premium = consultas => ({
    gratis: 20,
    restantes: 20,
    precos: ['0.09', '0.12'],
    confere_documento: true,
    consultas,
  });

  const montarPremium = async (id, dados) => {
    const wrapper = await montar(id, [{ chave: id, premium: dados }]);
    await wrapper.setProps({ premium: dados });
    return wrapper;
  };

  it('shows the count the server sends', async () => {
    const wrapper = await montarPremium('conferir_pessoa', premium(2));

    expect(wrapper.text()).toContain('Responde 2 tipos de pergunta');
  });

  it('shows no count when the card answers a single question', async () => {
    const wrapper = await montarPremium('certidoes_empresa', premium(1));

    expect(wrapper.text()).not.toContain('tipos de pergunta');
  });

  it('keeps the catalog count on a free card', async () => {
    const wrapper = await montar('fipe', [{ chave: 'fipe' }]);

    expect(wrapper.text()).toContain('Responde 3 tipos de pergunta');
  });
});
