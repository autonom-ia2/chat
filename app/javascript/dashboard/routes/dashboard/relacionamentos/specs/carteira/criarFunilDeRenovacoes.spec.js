import { defineComponent } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import {
  FUNIL_INCOMPLETO,
  MODELO_DAS_RENOVACOES,
  useCriarFunilDeRenovacoes,
} from '../../carteira/useCriarFunilDeRenovacoes';

// #3057 — "Criar o funil de renovações para mim" é o caminho do CRM com o
// modelo Renovação: o mesmo pedido que a gaveta de funil monta
// (useFunilModelo + payloadDoFunil) e a mesma ação do CRM que grava. A loja e a
// permissão do CRM são de mentira; os textos são os de verdade em pt_BR.
const loja = vi.hoisted(() => ({ dispatch: null, pacote: null, funis: [] }));
vi.mock('vuex', async importOriginal => ({
  ...(await importOriginal()),
  useStore: () => ({
    dispatch: (...args) => loja.dispatch(...args),
    getters: {
      getCurrentAccountId: 1,
      'accounts/getAccount': () => ({ id: 1, autonomia_pacote: loja.pacote }),
      get 'crmKanban/getPipelines'() {
        return loja.funis;
      },
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
  loja.funis = [{ id: 1, name: 'Vendas' }];
  crm.gerenciaFunis = true;
});

// A ação do CRM grava o funil, põe na lista do CRM e só depois grava as
// etapas: se uma etapa falha, o funil já existe.
describe('quando o pedido falha', () => {
  it('antes de o funil nascer, devolve o erro do pedido', async () => {
    const falha = new Error('Request failed with status code 500');
    loja.dispatch = vi.fn(async () => {
      throw falha;
    });

    await expect(usar().criar()).rejects.toBe(falha);
  });

  it('com o funil já na lista do CRM, diz que ele nasceu sem todas as etapas', async () => {
    loja.dispatch = vi.fn(async () => {
      loja.funis = [{ id: 9, name: 'Renovação' }, ...loja.funis];
      throw new Error('Request failed with status code 422');
    });

    await expect(usar().criar()).rejects.toMatchObject({
      name: FUNIL_INCOMPLETO,
      funil: { id: 9, name: 'Renovação' },
    });
  });
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
