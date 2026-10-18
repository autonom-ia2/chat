import { mount } from '@vue/test-utils';
import TelaInicialSaudacao from '../TelaInicialSaudacao.vue';
import TelaInicialResumo from '../TelaInicialResumo.vue';
import TelaInicialMarca from '../TelaInicialMarca.vue';

// #1801 — cada opção tem uma ação principal; sem nada esperando, troca pela ação do vazio.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) => `${key}=${valores?.count}`,
  }),
}));

const proxima = { displayId: 12, nome: 'Marina', desde: 1 };

const dadosCom = (extra = {}) => ({
  nome: 'John',
  saudacao: 'Boa tarde, John',
  hoje: 'sábado, 18 de outubro',
  nomeDaConta: 'Acme',
  logo: '',
  estado: 'pronto',
  pronto: true,
  esperamVoce: 1,
  semResponsavel: 2,
  foraDoPrazo: null,
  proxima,
  equipe: null,
  comVoce: 4,
  tudoEmDia: false,
  nomeDoCliente: item => item?.nome || '',
  esperaHa: () => '3 horas',
  abrir: vi.fn(),
  verMinhas: vi.fn(),
  verSemResponsavel: vi.fn(),
  verTodas: vi.fn(),
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

  it('o número maior que zero leva à lista certa', async () => {
    const dados = dadosCom({ foraDoPrazo: 3 });
    const wrapper = montar(TelaInicialResumo, dados);
    await wrapper.find('[data-numero="ESPERAM"]').trigger('click');
    await wrapper.find('[data-numero="SEM_RESPONSAVEL"]').trigger('click');
    expect(dados.verMinhas).toHaveBeenCalledTimes(1);
    expect(dados.verSemResponsavel).toHaveBeenCalledTimes(1);
    await wrapper.find('[data-numero="FORA_DO_PRAZO"]').trigger('click');
    expect(dados.verMinhas).toHaveBeenCalledTimes(2);
  });

  it('número zero não é clicável e não troca a aba', async () => {
    const dados = dadosCom({
      esperamVoce: 0,
      semResponsavel: 0,
      foraDoPrazo: 0,
    });
    const wrapper = montar(TelaInicialResumo, dados);
    const zerados = wrapper.findAll('[data-numero]');
    expect(zerados).toHaveLength(3);
    zerados.forEach(item => {
      expect(item.element.tagName).toBe('DIV');
      expect(item.attributes('data-clicavel')).toBeUndefined();
    });
    await zerados[0].trigger('click');
    await zerados[1].trigger('click');
    expect(dados.verMinhas).not.toHaveBeenCalled();
    expect(dados.verSemResponsavel).not.toHaveBeenCalled();
  });
});

describe('opção 2: equipe', () => {
  it('agente comum não vê a linha da equipe', () => {
    const wrapper = montar(TelaInicialResumo, dadosCom());
    expect(wrapper.find('[data-equipe]').exists()).toBe(false);
  });

  it('quem vê a conta tem a linha, clicável para todas', async () => {
    const dados = dadosCom({
      equipe: { esperam: 12, semResponsavel: 4, foraDoPrazo: 3 },
    });
    const wrapper = montar(TelaInicialResumo, dados);
    const linha = wrapper.find('[data-equipe]');
    expect(linha.text()).toContain('TELA_INICIAL.OPCAO_2.EQUIPE.ESPERAM=12');
    expect(linha.text()).toContain(
      'TELA_INICIAL.OPCAO_2.EQUIPE.FORA_DO_PRAZO=3'
    );
    await linha.trigger('click');
    expect(dados.verTodas).toHaveBeenCalled();
  });

  it('equipe sem prazos e sem ninguém esperando: só texto, sem clique', async () => {
    const dados = dadosCom({
      equipe: { esperam: 0, semResponsavel: 0, foraDoPrazo: null },
    });
    const wrapper = montar(TelaInicialResumo, dados);
    const linha = wrapper.find('[data-equipe]');
    expect(linha.element.tagName).toBe('P');
    expect(linha.text()).not.toContain('FORA_DO_PRAZO');
    await linha.trigger('click');
    expect(dados.verTodas).not.toHaveBeenCalled();
  });
});

describe('opção 2: carregando e erro', () => {
  it('enquanto carrega, mostra traço e nenhuma ação', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ estado: 'carregando', pronto: false })
    );
    expect(wrapper.find('[data-numero="ESPERAM"]').text()).toContain('–');
    expect(wrapper.find('[data-numero="ESPERAM"]').element.tagName).toBe('DIV');
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
