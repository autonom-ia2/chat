import { mount } from '@vue/test-utils';
import TelaInicialResumo from '../TelaInicialResumo.vue';

// #1801 — uma ação principal; sem nada esperando, troca pela ação do vazio.
// #2211: "3 das suas 4" só com a chave lista_quem_espera.
const listaNova = vi.hoisted(() => ({ value: true }));
vi.mock(
  'dashboard/components-next/Conversation/ListaDeConversas/useListaNova',
  () => ({ useListaNova: () => listaNova })
);

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) => `${key}=${valores?.count}`,
  }),
}));

const proxima = { displayId: 12, nome: 'Marina', desde: 1 };

const dadosCom = (extra = {}) => ({
  hoje: 'sábado, 18 de outubro',
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
  verEsperam: vi.fn(),
  verSemResponsavel: vi.fn(),
  verTodas: vi.fn(),
  verEquipe: vi.fn(),
  tentarDeNovo: vi.fn(),
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

describe('ação principal', () => {
  it('abre a conversa que espera há mais tempo', async () => {
    const dados = dadosCom();
    const wrapper = montar(TelaInicialResumo, dados);
    await wrapper.find('[data-abrir-proxima]').trigger('click');
    expect(dados.abrir).toHaveBeenCalledWith(proxima);
    expect(wrapper.find('[data-acao-do-vazio]').exists()).toBe(false);
  });

  it('sem nada esperando, mostra só a ação do vazio', async () => {
    const dados = dadosCom({ esperamVoce: 0, proxima: null, tudoEmDia: true });
    const wrapper = montar(TelaInicialResumo, dados);
    expect(wrapper.find('[data-abrir-proxima]').exists()).toBe(false);
    await wrapper.find('[data-acao-do-vazio]').trigger('click');
    expect(dados.acaoDoVazio.fazer).toHaveBeenCalled();
  });
});

describe('números', () => {
  it('sem prazo de resposta na conta, mostra dois números', () => {
    const wrapper = montar(TelaInicialResumo, dadosCom());
    expect(wrapper.findAll('[data-numero]')).toHaveLength(2);
  });

  it('o número maior que zero leva à lista certa', async () => {
    const dados = dadosCom({ foraDoPrazo: 3 });
    const wrapper = montar(TelaInicialResumo, dados);
    await wrapper.find('[data-numero="ESPERAM"]').trigger('click');
    await wrapper.find('[data-numero="SEM_RESPONSAVEL"]').trigger('click');
    expect(dados.verEsperam).toHaveBeenCalledTimes(1);
    expect(dados.verSemResponsavel).toHaveBeenCalledTimes(1);
  });

  it('fora do prazo só informa: não há lista dele para abrir', () => {
    const wrapper = montar(TelaInicialResumo, dadosCom({ foraDoPrazo: 3 }));
    const fora = wrapper.find('[data-numero="FORA_DO_PRAZO"]');
    expect(fora.element.tagName).toBe('DIV');
    expect(fora.attributes('data-clicavel')).toBeUndefined();
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
    expect(dados.verEsperam).not.toHaveBeenCalled();
    expect(dados.verSemResponsavel).not.toHaveBeenCalled();
  });
});

describe('sem a próxima', () => {
  it('ninguém esperando mas algo fora do prazo: título do resumo e a ação do vazio', async () => {
    const dados = dadosCom({ esperamVoce: 0, proxima: null, foraDoPrazo: 2 });
    const wrapper = montar(TelaInicialResumo, dados);
    expect(wrapper.text()).toContain('TELA_INICIAL.RESUMO.TITULO');
    expect(wrapper.find('[data-abrir-proxima]').exists()).toBe(false);
    await wrapper.find('[data-acao-do-vazio]').trigger('click');
    expect(dados.acaoDoVazio.fazer).toHaveBeenCalled();
  });

  it('contato sem nome: a frase da espera sem o nome', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ proxima: { ...proxima, nome: '' } })
    );
    expect(wrapper.text()).toContain('TELA_INICIAL.PROXIMA_ESPERA_SEM_NOME');
  });
});

describe('equipe', () => {
  it('agente comum não vê a linha da equipe', () => {
    const wrapper = montar(TelaInicialResumo, dadosCom());
    expect(wrapper.find('[data-equipe]').exists()).toBe(false);
  });

  it('quem vê a conta tem a linha, clicável para todas', async () => {
    const dados = dadosCom({
      equipe: { esperam: 12, foraDoPrazo: 3 },
    });
    const wrapper = montar(TelaInicialResumo, dados);
    const linha = wrapper.find('[data-equipe]');
    expect(linha.text()).toContain('TELA_INICIAL.RESUMO.EQUIPE.ESPERAM=12');
    expect(linha.text()).toContain(
      'TELA_INICIAL.RESUMO.EQUIPE.FORA_DO_PRAZO=3'
    );
    await linha.trigger('click');
    expect(dados.verEquipe).toHaveBeenCalled();
  });

  it('equipe sem prazos e sem ninguém esperando: só texto, sem clique', async () => {
    const dados = dadosCom({
      equipe: { esperam: 0, foraDoPrazo: null },
    });
    const wrapper = montar(TelaInicialResumo, dados);
    const linha = wrapper.find('[data-equipe]');
    expect(linha.element.tagName).toBe('P');
    expect(linha.text()).not.toContain('FORA_DO_PRAZO');
    await linha.trigger('click');
    expect(dados.verEquipe).not.toHaveBeenCalled();
  });
});

describe('carregando e erro', () => {
  it('enquanto carrega, mostra traço e nenhuma ação', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ estado: 'carregando', pronto: false })
    );
    expect(wrapper.find('[data-numero="ESPERAM"]').text()).toContain(
      'TELA_INICIAL.RESUMO.CARREGANDO'
    );
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
    expect(wrapper.text()).not.toContain('COM_VOCE');
    expect(wrapper.find('[data-abrir-proxima]').exists()).toBe(false);
  });
});

describe('rodapé "Como vai o seu mês" (#1897)', () => {
  const comRodape = comoVaiOMes =>
    mount(TelaInicialResumo, {
      props: { dados: dadosCom(), comoVaiOMes },
      global: {
        mocks: { $t: key => key },
        stubs: { RouterLink: { template: '<a><slot /></a>' } },
      },
    });

  it('só no computador: escondido no celular, visível a partir do md', () => {
    const link = comRodape({ name: 'crm_dashboard_index', query: {} }).find(
      '[data-como-vai-o-mes]'
    );
    const caixa = link.element.parentElement.classList;
    expect(caixa.contains('hidden')).toBe(true);
    expect(caixa.contains('md:block')).toBe(true);
  });

  it('sem destino, não há rodapé', () => {
    expect(comRodape(null).find('[data-como-vai-o-mes]').exists()).toBe(false);
  });
});

describe('"3 das suas 4 esperam você" (#2211)', () => {
  beforeEach(() => {
    listaNova.value = true;
  });

  it('com a chave desligada, fica "Esperam você" como na main', () => {
    listaNova.value = false;
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ esperamVoce: 3, comVoce: 4 })
    );
    const texto = wrapper.find('[data-numero="ESPERAM"]').text();
    expect(texto).toContain('TELA_INICIAL.RESUMO.NUMEROS.ESPERAM');
    expect(texto).not.toContain('ESPERAM_DAS_SUAS');
  });

  it('com mais de uma conversa, o rótulo diz de quantas', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ esperamVoce: 3, comVoce: 4 })
    );
    expect(wrapper.find('[data-numero="ESPERAM"]').text()).toContain(
      'TELA_INICIAL.RESUMO.NUMEROS.ESPERAM_DAS_SUAS'
    );
  });

  it('com uma conversa só, fica "Esperam você"', () => {
    const wrapper = montar(
      TelaInicialResumo,
      dadosCom({ esperamVoce: 1, comVoce: 1 })
    );
    const texto = wrapper.find('[data-numero="ESPERAM"]').text();
    expect(texto).toContain('TELA_INICIAL.RESUMO.NUMEROS.ESPERAM');
    expect(texto).not.toContain('ESPERAM_DAS_SUAS');
  });

  it('o número de "Sem responsável" não muda de rótulo', () => {
    const wrapper = montar(TelaInicialResumo, dadosCom({ comVoce: 4 }));
    expect(wrapper.find('[data-numero="SEM_RESPONSAVEL"]').text()).toContain(
      'TELA_INICIAL.RESUMO.NUMEROS.SEM_RESPONSAVEL'
    );
  });
});
