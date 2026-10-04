import { mount, flushPromises } from '@vue/test-utils';
import AutomationAPI from 'dashboard/api/automation';
import AutomacaoEnsaio from '../components/AutomacaoEnsaio.vue';

// #859 — "Testar com casos reais": mostra o que a regra faria, o que ficou de
// fora do teste e o erro com o próximo passo.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key, valores) => (valores ? `${key}` : key) }),
}));
vi.mock('dashboard/api/automation', () => ({
  default: { ensaio: vi.fn() },
}));

const montar = () =>
  mount(AutomacaoEnsaio, {
    props: { regraId: 42, accountId: 1 },
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key} ${JSON.stringify(valores)}` : key,
      },
      stubs: { RouterLink: { template: '<a><slot /></a>' } },
    },
  });

describe('AutomacaoEnsaio', () => {
  beforeEach(() => vi.clearAllMocks());

  it('testa nas conversas recentes e mostra quantas seriam afetadas', async () => {
    AutomationAPI.ensaio.mockResolvedValue({
      data: {
        resultados: [
          {
            conversation_id: 1,
            display_id: 10,
            contato: 'Maria',
            casou: true,
            faria: ['add_label'],
          },
          {
            conversation_id: 2,
            display_id: 11,
            contato: null,
            casou: false,
            faria: [],
          },
        ],
        sem_teste: ['status'],
      },
    });
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(AutomationAPI.ensaio).toHaveBeenCalledWith(42, 10);
    expect(wrapper.find('[data-ensaio-resumo]').text()).toContain(
      '"casaram":1,"total":2'
    );
    const itens = wrapper.findAll('[data-ensaio-item]');
    expect(itens[0].text()).toContain('Maria');
    expect(itens[0].text()).toContain('AUTOMACOES.ENSAIO.CASARIA');
    expect(itens[1].text()).toContain('AUTOMACOES.ENSAIO.CONTATO_SEM_NOME');
    expect(wrapper.find('[data-sem-teste]').exists()).toBe(true);
  });

  // Revisão de integração (#858 x #859): o teste não pergunta ao Decisor; os
  // passos depois dele aparecem como dependentes da resposta, não como certos.
  it('passos depois do Decisor aparecem como dependentes da resposta', async () => {
    AutomationAPI.ensaio.mockResolvedValue({
      data: {
        resultados: [
          {
            conversation_id: 1,
            display_id: 10,
            contato: 'Maria',
            casou: true,
            faria: ['add_label', 'perguntar_ao_decisor'],
          },
        ],
        sem_teste: [],
        depende_do_decisor: ['send_message'],
      },
    });
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-sem-teste]').exists()).toBe(false);
    expect(wrapper.find('[data-depende-do-decisor]').text()).toContain(
      'AUTOMACOES.ENSAIO.DEPENDE_DO_DECISOR'
    );
    expect(wrapper.find('[data-ensaio-item]').text()).toContain(
      'AUTOMACOES.ENSAIO.FARIA'
    );
  });

  it('sem Decisor, não fala de Decisor', async () => {
    AutomationAPI.ensaio.mockResolvedValue({
      data: { resultados: [], sem_teste: [] },
    });
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-depende-do-decisor]').exists()).toBe(false);
  });

  it('sem conversa na conta, diz isso', async () => {
    AutomationAPI.ensaio.mockResolvedValue({
      data: { resultados: [], sem_teste: [] },
    });
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-ensaio-vazio]').exists()).toBe(true);
  });

  // Revisão #859: regra só com "mudou de valor" não lista conversas como se
  // todas fossem afetadas — diz que não dá para testar e por quê.
  it('regra que só age quando algo muda: diz que não dá para testar', async () => {
    AutomationAPI.ensaio.mockResolvedValue({
      data: { testavel: false, resultados: [], sem_teste: ['status'] },
    });
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-nao-testavel]').exists()).toBe(true);
    expect(wrapper.find('[data-ensaio-resumo]').exists()).toBe(false);
    expect(wrapper.find('[data-ensaio-vazio]').exists()).toBe(false);
    expect(wrapper.findAll('[data-ensaio-item]')).toHaveLength(0);
  });

  it('erro mostra o motivo do servidor ou pede para tentar de novo', async () => {
    AutomationAPI.ensaio
      .mockRejectedValueOnce({
        response: { data: { error: 'Condição inválida.' } },
      })
      .mockRejectedValueOnce(new Error('rede'));
    const wrapper = montar();

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-ensaio-erro]').text()).toBe(
      'Condição inválida.'
    );

    await wrapper.find('[data-testar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-ensaio-erro]').text()).toBe(
      'AUTOMACOES.ENSAIO.ERRO'
    );
  });
});
