import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import AgenteSilencios from '../../components/pagina/AgenteSilencios.vue';

// #1709 — "Quando {nome} não respondeu" (mockup aprovado em 17/10/2026): os silêncios de propósito da semana.
const api = vi.hoisted(() => ({ analytics: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: api }));

withFullI18n();

const COM_CONVERSA = { respondidas: 3, passadas: 1 };

const montar = (props = {}) =>
  mount(AgenteSilencios, {
    props: { agentId: 7, nome: 'Bia', numeros: COM_CONVERSA, ...props },
  });

describe('AgenteSilencios', () => {
  beforeEach(() => api.analytics.mockReset());

  it('lists each silence with its count and the agent name, this week', async () => {
    api.analytics.mockResolvedValue({
      data: {
        silences: [
          { reason: 'mensagem_sem_suporte', count: 2 },
          { reason: 'escolha_retirada', count: 1 },
          { reason: 'outro', count: 9 },
        ],
      },
    });

    const wrapper = montar();
    await flushPromises();

    expect(api.analytics).toHaveBeenCalledWith(7, { range: '7d' });
    expect(wrapper.text()).toContain('When Bia did not answer');
    expect(wrapper.text()).toContain('This week, Bia did not answer');
    const linhas = wrapper.findAll('[data-motivo]');
    expect(linhas.map(linha => linha.attributes('data-motivo'))).toEqual([
      'mensagem_sem_suporte',
      'escolha_retirada',
    ]);
    expect(linhas[0].text()).toContain('2 times');
    expect(linhas[1].text()).toContain('1 time');
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.find('a').exists()).toBe(false);
  });

  it('says the agent never stayed quiet when there was a conversation and no silence', async () => {
    api.analytics.mockResolvedValue({ data: { silences: [] } });

    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'Bia did not skip an answer even once this week.'
    );
    expect(wrapper.findAll('[data-motivo]')).toHaveLength(0);
  });

  it('hides the block when there was no conversation this week', async () => {
    api.analytics.mockResolvedValue({ data: { silences: [] } });

    const semNumeros = montar({ numeros: null });
    const zero = montar({ numeros: { respondidas: 0, passadas: 0 } });
    await flushPromises();

    expect(semNumeros.find('[data-bloco="silencios"]').exists()).toBe(false);
    expect(zero.find('[data-bloco="silencios"]').exists()).toBe(false);
    expect(api.analytics).not.toHaveBeenCalled();
  });

  it('hides the block for an agent that does not talk to the customer', async () => {
    api.analytics.mockResolvedValue({
      data: { silences: [{ reason: 'mensagem_apagada', count: 1 }] },
    });

    const wrapper = montar({ falaComCliente: false });
    await flushPromises();

    expect(wrapper.find('[data-bloco="silencios"]').exists()).toBe(false);
    expect(api.analytics).not.toHaveBeenCalled();
  });

  it('hides the block when the API fails, and logs only the status', async () => {
    const aviso = vi.spyOn(console, 'warn').mockImplementation(() => {});
    api.analytics.mockRejectedValueOnce({
      response: { status: 500, data: { cliente: 'Quero cancelar' } },
    });

    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[data-bloco="silencios"]').exists()).toBe(false);
    expect(aviso).toHaveBeenCalledWith(
      '[agentes] silencios: leitura falhou',
      500
    );
    expect(JSON.stringify(aviso.mock.calls)).not.toContain('Quero cancelar');
    aviso.mockRestore();
  });

  it('drops the answer of the previous agent when it arrives after the switch', async () => {
    let soltarAntiga;
    api.analytics
      .mockImplementationOnce(
        () =>
          new Promise(resolver => {
            soltarAntiga = resolver;
          })
      )
      .mockResolvedValueOnce({
        data: { silences: [{ reason: 'mensagem_apagada', count: 1 }] },
      });

    const wrapper = montar();
    await wrapper.setProps({ agentId: 8, nome: 'Caio' });
    await flushPromises();
    soltarAntiga({
      data: { silences: [{ reason: 'mensagem_sem_suporte', count: 9 }] },
    });
    await flushPromises();

    expect(api.analytics).toHaveBeenNthCalledWith(2, 8, { range: '7d' });
    const linhas = wrapper.findAll('[data-motivo]');
    expect(linhas.map(linha => linha.attributes('data-motivo'))).toEqual([
      'mensagem_apagada',
    ]);
    expect(wrapper.text()).toContain('When Caio did not answer');
  });
});
