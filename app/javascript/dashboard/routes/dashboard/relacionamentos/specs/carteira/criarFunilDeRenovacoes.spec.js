import { defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  MODELO_DAS_RENOVACOES,
  useCriarFunilDeRenovacoes,
} from '../../carteira/useCriarFunilDeRenovacoes';

// #3057 — "Criar o funil de renovações para mim" é o caminho do CRM com o
// modelo Renovação: o mesmo pedido que a gaveta de funil monta
// (useFunilModelo + payloadDoFunil) e a mesma ação do CRM que grava. A loja e a
// permissão do CRM são de mentira; os textos são os de verdade em pt_BR.
const loja = vi.hoisted(() => ({ dispatch: null, pacote: null }));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({
    dispatch: (...args) => loja.dispatch(...args),
    getters: {
      getCurrentAccountId: 1,
      'accounts/getAccount': () => ({ id: 1, autonomia_pacote: loja.pacote }),
    },
  }),
}));
const crm = vi.hoisted(() => ({ gerenciaFunis: true }));
vi.mock(
  'dashboard/routes/dashboard/crm/composables/useCrmPermissions',
  async () => {
    const { computed } = await import('vue');
    return {
      useCrmPermissions: () => ({
        canManagePipelines: computed(() => crm.gerenciaFunis),
      }),
    };
  }
);

withFullI18n('pt_BR');

const usar = () => {
  let criacao;
  mount(
    defineComponent({
      setup() {
        criacao = useCriarFunilDeRenovacoes();
        return () => null;
      },
    })
  );
  return criacao;
};

beforeEach(() => {
  loja.dispatch = vi.fn(async () => ({ id: 9, name: 'Renovação' }));
  loja.pacote = null;
  crm.gerenciaFunis = true;
});

describe('quem pode criar o funil', () => {
  it('é quem pode criar funil no CRM (a regra do botão "Criar funil")', () => {
    expect(usar().podeCriar.value).toBe(true);

    crm.gerenciaFunis = false;

    expect(usar().podeCriar.value).toBe(false);
  });
});

describe('o funil criado', () => {
  const pedido = () => loja.dispatch.mock.calls[0][1];

  it('sai pela ação do CRM que grava funil e etapas, e devolve o funil', async () => {
    const funil = await usar().criar();

    expect(loja.dispatch).toHaveBeenCalledTimes(1);
    expect(loja.dispatch.mock.calls[0][0]).toBe(
      'crmKanban/savePipelineWithStages'
    );
    expect(funil).toEqual({ id: 9, name: 'Renovação' });
  });

  it('é o do modelo Renovação: nome, tipo Vender, desfechos e "Quando usar"', async () => {
    await usar().criar();
    const { pipeline } = pedido();

    expect(MODELO_DAS_RENOVACOES).toBe('RENOVACAO');
    expect(pipeline).toMatchObject({
      template: 'RENOVACAO',
      name: 'Renovação',
      counts_as_sale: true,
      outcome_labels: { success: 'Renovou', failure: 'Não renovou' },
      when_to_use: 'está com o seguro perto de vencer',
    });
    expect(pipeline.id).toBeUndefined();
  });

  it('traz as cinco etapas do modelo, na ordem, com a posição de cada uma', async () => {
    await usar().criar();
    const { stages } = pedido();

    expect(stages.map(etapa => etapa.name)).toEqual([
      'A vencer',
      'Cotando',
      'Opções enviadas',
      'Negociação',
      'Renovado',
    ]);
    expect(stages.map(etapa => etapa.template_position)).toEqual([
      1, 2, 3, 4, 5,
    ]);
    // A frase de cada etapa para a IA fica com o servidor (a padrão do modelo).
    stages.forEach(etapa => expect(etapa).not.toHaveProperty('aiCriteria'));
  });

  // O modelo tem a camada da corretora, mas ela só decide a lista do CRM.
  it.each([null, 'seguros.corretora', 'seguros.saude_beneficios'])(
    'vale para a conta com o pacote %s',
    async pacote => {
      loja.pacote = pacote;

      await usar().criar();

      expect(pedido().pipeline.template).toBe('RENOVACAO');
      expect(pedido().stages).toHaveLength(5);
    }
  );

  it('diz que está criando enquanto o pedido anda, e devolve o erro dele', async () => {
    let terminar;
    loja.dispatch = vi.fn(
      () =>
        new Promise((_, recusar) => {
          terminar = recusar;
        })
    );
    const criacao = usar();

    const pedindo = criacao.criar();
    expect(criacao.criando.value).toBe(true);
    terminar(new Error('caiu'));

    await expect(pedindo).rejects.toThrow('caiu');
    await flushPromises();
    expect(criacao.criando.value).toBe(false);
  });

  it('tentar de novo manda o mesmo funil', async () => {
    const criacao = usar();

    await criacao.criar();
    await criacao.criar();

    expect(loja.dispatch.mock.calls[1][1]).toEqual(
      loja.dispatch.mock.calls[0][1]
    );
  });
});
