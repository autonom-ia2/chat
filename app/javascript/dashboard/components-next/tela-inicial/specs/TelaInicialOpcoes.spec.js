import { mount } from '@vue/test-utils';
import TelaInicialSaudacao from '../TelaInicialSaudacao.vue';
import TelaInicialResumo from '../TelaInicialResumo.vue';
import TelaInicialMarca from '../TelaInicialMarca.vue';

// #1801 — cada opção tem uma ação principal; sem nada esperando, troca pela ação do vazio.
const proxima = {
  id: 12,
  waiting_since: 1,
  meta: { sender: { name: 'Marina' } },
};

const dadosCom = (extra = {}) => ({
  nome: 'John',
  saudacao: 'Boa tarde, John',
  hoje: 'sábado, 18 de outubro',
  nomeDaConta: 'Acme',
  logo: '',
  estado: 'pronto',
  pronto: true,
  esperamVoce: 1,
  proxima,
  atrasadas: null,
  comVoce: 4,
  esperamAlguem: 2,
  tudoEmDia: false,
  nomeDoCliente: conversa => conversa?.meta?.sender?.name || '',
  esperaHa: () => '3 horas',
  abrir: vi.fn(),
  verMinhas: vi.fn(),
  verSemResponsavel: vi.fn(),
  acaoDoVazio: { rotulo: 'VER_SEM_RESPONSAVEL', fazer: vi.fn() },
  ...extra,
});

const montar = (componente, dados) =>
  mount(componente, {
    props: { dados },
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key} ${JSON.stringify(valores)}` : key,
      },
    },
  });

describe.each([
  ['opção 1', TelaInicialSaudacao],
  ['opção 2', TelaInicialResumo],
  ['opção 3', TelaInicialMarca],
])('%s', (_nome, componente) => {
  it('abre a conversa que espera há mais tempo', async () => {
    const dados = dadosCom();
    const wrapper = montar(componente, dados);
    await wrapper.find('[data-abrir-proxima]').trigger('click');
    expect(dados.abrir).toHaveBeenCalledWith(proxima);
    expect(wrapper.find('[data-acao-do-vazio]').exists()).toBe(false);
  });

  it('sem nada esperando, mostra só a ação do vazio', async () => {
    const dados = dadosCom({ esperamVoce: 0, proxima: null, tudoEmDia: true });
    const wrapper = montar(componente, dados);
    expect(wrapper.find('[data-abrir-proxima]').exists()).toBe(false);
    await wrapper.find('[data-acao-do-vazio]').trigger('click');
    expect(dados.acaoDoVazio.fazer).toHaveBeenCalled();
  });
});

describe('opção 2: números', () => {
  it('sem prazo de resposta na conta, mostra dois números', () => {
    const wrapper = montar(TelaInicialResumo, dadosCom());
    expect(wrapper.findAll('[data-numero]')).toHaveLength(2);
  });

  it('o número leva à lista certa e o fora do prazo abre a mais atrasada', async () => {
    const atrasada = { id: 99 };
    const dados = dadosCom({ atrasadas: [atrasada] });
    const wrapper = montar(TelaInicialResumo, dados);
    await wrapper.find('[data-numero="ESPERAM"]').trigger('click');
    await wrapper.find('[data-numero="ESPERAM_ALGUEM"]').trigger('click');
    await wrapper.find('[data-numero="FORA_DO_PRAZO"]').trigger('click');
    expect(dados.verMinhas).toHaveBeenCalled();
    expect(dados.verSemResponsavel).toHaveBeenCalled();
    expect(dados.abrir).toHaveBeenCalledWith(atrasada);
  });
});

describe('opção 2: carregando e erro', () => {
  it('enquanto carrega, mostra traço e nenhuma ação', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ estado: 'carregando', pronto: false })
    );
    expect(wrapper.find('[data-numero="ESPERAM"]').text()).toContain('–');
    expect(wrapper.find('[data-abrir-proxima]').exists()).toBe(false);
    expect(wrapper.find('[data-acao-do-vazio]').exists()).toBe(false);
  });

  it('sem conseguir carregar, avisa', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ estado: 'erro', pronto: false })
    );
    expect(wrapper.find('[data-erro]').exists()).toBe(true);
    expect(wrapper.find('[data-abrir-proxima]').exists()).toBe(false);
  });
});
