import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AjustarRenovacoesPage from '../../pages/AjustarRenovacoesPage.vue';
import { esquecerAjustesDaDemo } from '../../demo/carteiraAjustes';
import { usarDemo } from '../../fonte/modoDemo';
import { assentar, carregarDemonstracao, daCarteira, erroHttp } from './apoio';

// "Ajustar renovações" (#2898) com o texto de verdade em pt_BR: em que funil e
// etapa a renovação aparece, quantos dias antes do fim e se as mensagens saem.
// Fora da demonstração a tela fala com o servidor (o cliente de API é de
// mentira). Conta sem a carteira de seguros não chama rota nenhuma. Todos os
// dados são inventados.
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: { renovacoes: vi.fn(), salvarRenovacoes: vi.fn() },
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: vi.fn(),
}));
// A conta aberta, como o servidor manda: `carteira_seguros` liga a carteira.
const conta = vi.hoisted(() => ({ carteira_seguros: true }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: conta } }),
}));
// Quem olha pode mudar os ajustes? (o composable devolve um `computed`; a
// regra das duas chaves é conferida em permissoesDaRenovacao.spec.js)
const assento = vi.hoisted(() => ({ ajusta: true }));
vi.mock('../../carteira/usePodeAjustarRenovacoes', async () => {
  const { computed } = await import('vue');
  return { usePodeAjustarRenovacoes: () => computed(() => assento.ajusta) };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = { push: vi.fn(), replace: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const roteador = useRouter();

const FUNIS = [
  {
    id: 1,
    nome: 'Renovação',
    etapas: [
      { id: 11, nome: 'A vencer' },
      { id: 12, nome: 'Em conversa' },
    ],
  },
  { id: 2, nome: 'Vendas', etapas: [{ id: 21, nome: 'Novo contato' }] },
];
const ESCOLHAS = { funilId: 1, etapaId: 11, dias: 60, mensagens: 'mandar' };
const SEM_ESCOLHA = { ...ESCOLHAS, funilId: null, etapaId: null };
// A conta que ainda não tem as mensagens de renovação: o servidor não manda a
// escolha delas.
const SEM_MENSAGENS = { funilId: 1, etapaId: 11, dias: 60 };
// O que o servidor manda em `GET seguros/renovacoes`.
const doServidor = (mudancas = {}) => ({
  ajustes: ESCOLHAS,
  funis: FUNIS,
  vencimentos: [3, 20, 61],
  semPermissao: false,
  exemplo: null,
  ...mudancas,
});
const servidorResponde = mudancas =>
  SegurosAPI.renovacoes.mockResolvedValue({ data: doServidor(mudancas) });
// O servidor guarda e devolve o que recebeu.
const servidorGuarda = () =>
  SegurosAPI.salvarRenovacoes.mockImplementation(async ajustes => ({
    data: ajustes,
  }));

let aberta;
const abrir = async ({ demo = null } = {}) => {
  usarDemo.mockReturnValue(demo);
  aberta = mount(AjustarRenovacoesPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const clicar = async (w, seletor) => {
  await w.get(seletor).trigger('click');
  await assentar();
};
const salvar = w => clicar(w, daCarteira('salvar-ajustes'));
const alerta = w => w.get(daCarteira('alerta-dos-ajustes')).text();
const temAlerta = w => w.find(daCarteira('alerta-dos-ajustes')).exists();
const salvos = w => w.get(daCarteira('ajustes-salvos')).text();
const campoDeDias = w => w.get(`${daCarteira('dias-antes')} input`);
const escreverDias = async (w, texto) => {
  await campoDeDias(w).setValue(texto);
  await assentar();
};
const escolhas = w => w.findAllComponents(ChoiceSelect);
const escolher = async (escolha, valor) => {
  escolha.vm.$emit('update:modelValue', valor);
  await assentar();
};

beforeAll(async () => {
  await carregarDemonstracao();
  await import('../../demo/carteiraAjustes.js');
  await import('../../demo/carteiraResultados.js');
}, 60000);
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  conta.carteira_seguros = true;
  assento.ajusta = true;
  SegurosAPI.renovacoes.mockReset();
  SegurosAPI.salvarRenovacoes.mockReset();
  roteador.push.mockClear();
  roteador.replace.mockClear();
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
  esquecerAjustesDaDemo();
});

describe('conta sem a carteira de seguros', () => {
  it('não chama rota nenhuma e volta para a lista', async () => {
    conta.carteira_seguros = false;

    const w = await abrir();

    expect(SegurosAPI.renovacoes).not.toHaveBeenCalled();
    expect(roteador.replace).toHaveBeenCalledWith({
      name: 'relationships_home',
    });
    expect(w.find('main').exists()).toBe(false);
    expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
  });
});

describe('o que a tela mostra', () => {
  it('três perguntas, já respondidas com o que a conta escolheu', async () => {
    servidorResponde();

    const w = await abrir();

    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(1);
    expect(roteador.replace).not.toHaveBeenCalled();
    expect(w.get('[data-titulo-da-tela]').text()).toBe('Ajustar renovações');
    expect(w.get(`${daCarteira('ajuste-onde')} h2`).text()).toBe(
      'Onde ficam as renovações?'
    );
    expect(w.get(`${daCarteira('ajuste-dias')} h2`).text()).toBe(
      'Quantos dias antes do fim?'
    );
    expect(w.get(`${daCarteira('ajuste-mensagens')} h2`).text()).toBe(
      'Mensagens antes de vencer'
    );
    const [funil, etapa] = escolhas(w);
    expect(funil.props('modelValue')).toBe(1);
    expect(etapa.props('modelValue')).toBe(11);
    expect(campoDeDias(w).element.value).toBe('60');
    expect(w.get('[data-resposta="mandar"]').attributes('aria-checked')).toBe(
      'true'
    );
  });

  it('uma ação só: Salvar ajustes, sempre ligado', async () => {
    servidorResponde();

    const w = await abrir();

    const botao = w.get(daCarteira('salvar-ajustes'));
    expect(botao.text()).toBe('Salvar ajustes');
    expect(botao.attributes('disabled')).toBeUndefined();
    expect(w.findAll('button[disabled]')).toHaveLength(0);
    expect(temAlerta(w)).toBe(false);
    expect(salvos(w)).toBe('');
  });

  it('o título recebe o foco ao abrir', async () => {
    servidorResponde();

    const w = await abrir();

    expect(document.activeElement).toBe(w.get('[data-titulo-da-tela]').element);
  });

  it('"Seguros" volta para a aba Seguros', async () => {
    servidorResponde();
    const w = await abrir();

    await clicar(w, '[data-relacionamentos="voltar"]');

    expect(roteador.push).toHaveBeenCalledWith({
      name: 'relationships_home',
      query: { aba: 'seguros' },
    });
  });

  it('na demonstração lê a conta fictícia, sem ir ao servidor', async () => {
    const w = await abrir({ demo: 'cheio' });
    await assentar();

    expect(SegurosAPI.renovacoes).not.toHaveBeenCalled();
    expect(w.find(daCarteira('ajuste-onde')).exists()).toBe(true);
    expect(escolhas(w)[0].props('modelValue')).toBe(1);
  });
});

describe('quantos dias antes', () => {
  it('diz quantos seguros já entram com o número de dias escrito', async () => {
    servidorResponde();

    const w = await abrir();

    expect(w.get(daCarteira('efeito-dias')).text()).toBe(
      'Com 60 dias, 2 seguros já entram em renovação.'
    );

    await escreverDias(w, '90');

    expect(w.get(daCarteira('efeito-dias')).text()).toBe(
      'Com 90 dias, 3 seguros já entram em renovação.'
    );
  });

  it('aceita a partir de 1 dia', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();

    await escreverDias(w, '1');

    expect(w.get(daCarteira('efeito-dias')).text()).toBe(
      'Com 1 dia, nenhum seguro entra em renovação agora.'
    );

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...ESCOLHAS,
      dias: 1,
    });
    expect(salvos(w)).toBe('Ajustes salvos.');
    expect(temAlerta(w)).toBe(false);
  });

  it.each(['0', '', 'dez', '1,5'])(
    'com %j no campo, Salvar diz o que falta e leva o foco até lá',
    async escrito => {
      servidorResponde();
      const w = await abrir();
      await escreverDias(w, escrito);

      await salvar(w);

      expect(alerta(w)).toBe('Escreva quantos dias antes, a partir de 1.');
      expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
      expect(document.activeElement).toBe(campoDeDias(w).element);
      expect(campoDeDias(w).attributes('aria-invalid')).toBe('true');
      expect(w.get(daCarteira('efeito-dias')).text()).toBe('');
    }
  );

  it('os botões de menos e mais mudam o número', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();

    await clicar(w, '[data-dias="menos"]');
    await clicar(w, '[data-dias="menos"]');

    expect(campoDeDias(w).element.value).toBe('58');

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...ESCOLHAS,
      dias: 58,
    });
  });
});

describe('o funil e a etapa', () => {
  it('conta que ainda não escolheu: Salvar pede o funil', async () => {
    servidorResponde({ ajustes: SEM_ESCOLHA });
    const w = await abrir();

    expect(w.text()).toContain(
      'Escolha em que funil as renovações ficam. Até lá, nenhuma renovação aparece.'
    );
    expect(escolhas(w)).toHaveLength(1);

    await salvar(w);

    expect(alerta(w)).toBe('Escolha o funil em que as renovações ficam.');
    expect(escolhas(w)[0].props('invalid')).toBe(true);
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
  });

  it('escolher o funil já escolhe a primeira etapa, e Salvar guarda os dois', async () => {
    servidorResponde({ ajustes: SEM_ESCOLHA });
    servidorGuarda();
    const w = await abrir();

    await escolher(escolhas(w)[0], 2);

    const [, etapa] = escolhas(w);
    expect(etapa.props('modelValue')).toBe(21);
    expect(etapa.props('options').map(o => o.label)).toEqual(['Novo contato']);

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      funilId: 2,
      etapaId: 21,
      dias: 60,
      mensagens: 'mandar',
    });
    expect(salvos(w)).toBe('Ajustes salvos.');
  });

  it('trocar só a etapa guarda a etapa nova', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();

    await escolher(escolhas(w)[1], 12);
    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...ESCOLHAS,
      etapaId: 12,
    });
  });

  it('conta sem funil: diz o que fazer e leva ao CRM, sem as outras perguntas', async () => {
    servidorResponde({ ajustes: SEM_ESCOLHA, funis: [] });
    const w = await abrir();

    expect(w.get(daCarteira('sem-funil')).text()).toContain(
      'Sua conta ainda não tem funil.'
    );
    expect(w.find(daCarteira('ajuste-dias')).exists()).toBe(false);
    expect(w.find(daCarteira('ajuste-mensagens')).exists()).toBe(false);
    expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
    expect(w.findAll('button[disabled]')).toHaveLength(0);

    await clicar(w, daCarteira('abrir-crm'));

    expect(roteador.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
  });
});

describe('as mensagens', () => {
  it('"Não mandar" é guardado', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();

    await clicar(w, '[data-resposta="nao_mandar"]');

    expect(
      w.get('[data-resposta="nao_mandar"]').attributes('aria-checked')
    ).toBe('true');

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...ESCOLHAS,
      mensagens: 'nao_mandar',
    });
  });

  it('as duas respostas têm nome', async () => {
    servidorResponde();
    const w = await abrir();

    expect(w.get('[data-resposta="mandar"]').text()).toBe('Mandar');
    expect(w.get('[data-resposta="nao_mandar"]').text()).toBe('Não mandar');
  });

  it('o servidor manda a escolha das mensagens: o cartão aparece', async () => {
    servidorResponde();

    const w = await abrir();

    expect(w.find(daCarteira('ajuste-mensagens')).exists()).toBe(true);
    expect(w.findAll('[data-resposta]')).toHaveLength(2);
  });

  it('o servidor não manda a escolha das mensagens: o cartão não é montado', async () => {
    servidorResponde({ ajustes: SEM_MENSAGENS });

    const w = await abrir();

    expect(w.find(daCarteira('ajuste-mensagens')).exists()).toBe(false);
    expect(w.findAll('[data-resposta]')).toHaveLength(0);
    expect(w.text()).not.toContain('Mensagens antes de vencer');
    expect(w.findAll('button[disabled]')).toHaveLength(0);
    expect(w.find(daCarteira('ajuste-onde')).exists()).toBe(true);
    expect(w.find(daCarteira('ajuste-dias')).exists()).toBe(true);
  });

  it('sem o cartão, Salvar não manda mensagens, e o cartão não nasce depois', async () => {
    servidorResponde({ ajustes: SEM_MENSAGENS });
    // O servidor devolve os ajustes inteiros, com o que a tela não mandou.
    SegurosAPI.salvarRenovacoes.mockImplementation(async ajustes => ({
      data: { ...ajustes, mensagens: 'mandar' },
    }));
    const w = await abrir();
    await escreverDias(w, '45');

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...SEM_MENSAGENS,
      dias: 45,
    });
    expect(salvos(w)).toBe('Ajustes salvos.');
    expect(w.find(daCarteira('ajuste-mensagens')).exists()).toBe(false);
  });

  it('na demonstração o cartão das mensagens aparece', async () => {
    const w = await abrir({ demo: 'cheio' });
    await assentar();

    expect(w.find(daCarteira('ajuste-mensagens')).exists()).toBe(true);
  });
});

describe('salvar', () => {
  it('sem mudar nada, diz que nada mudou e não vai ao servidor', async () => {
    servidorResponde();
    const w = await abrir();

    await salvar(w);

    expect(alerta(w)).toBe(
      'Você ainda não mudou nada. Mude o que quiser e salve.'
    );
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
  });

  it('mexer em qualquer coisa tira o aviso', async () => {
    servidorResponde();
    const w = await abrir();
    await salvar(w);

    await clicar(w, '[data-dias="mais"]');

    expect(temAlerta(w)).toBe(false);
  });

  it('depois de salvar, salvar de novo sem mudar diz que nada mudou', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();
    await escreverDias(w, '45');
    await salvar(w);

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledTimes(1);
    expect(alerta(w)).toBe(
      'Você ainda não mudou nada. Mude o que quiser e salve.'
    );
    expect(salvos(w)).toBe('');
  });

  it('funil que não existe mais: diz o que fazer e relê os funis', async () => {
    servidorResponde();
    SegurosAPI.salvarRenovacoes.mockRejectedValue(
      erroHttp(422, { error: 'funil_desconhecido' })
    );
    const w = await abrir();
    await escreverDias(w, '45');

    await salvar(w);

    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(2);
    expect(alerta(w)).toBe(
      'Esse funil não existe mais ou você não pode vê-lo. Atualizei a lista: escolha outro funil e salve de novo.'
    );
  });

  it('dias que o servidor recusa: a frase diz o que escrever, sem repetir o que foi escrito', async () => {
    servidorResponde();
    SegurosAPI.salvarRenovacoes.mockRejectedValue(
      erroHttp(422, { error: 'dias_invalidos' })
    );
    const w = await abrir();
    await escreverDias(w, '99999');

    await salvar(w);

    expect(alerta(w)).toBe(
      'Esse número de dias não serve. Escreva um número inteiro, de 1 a 3650, e salve de novo.'
    );
    expect(alerta(w)).not.toContain('99999');
    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(1);
  });

  it('outra falha: pede para tentar de novo e não perde o que foi escrito', async () => {
    servidorResponde();
    SegurosAPI.salvarRenovacoes.mockRejectedValue(erroHttp(500));
    const w = await abrir();
    await escreverDias(w, '45');

    await salvar(w);

    expect(alerta(w)).toBe('Não consegui salvar. Tente de novo.');
    expect(campoDeDias(w).element.value).toBe('45');
  });
});

describe('quem não pode mudar', () => {
  const HOJE =
    'Hoje as renovações ficam no funil Renovação, na etapa A vencer, e aparecem 60 dias antes do fim.';

  it('o servidor diz que não pode: lê a escolha de hoje e não vê Salvar', async () => {
    servidorResponde({ semPermissao: true });

    const w = await abrir();

    expect(w.get(daCarteira('escolha-de-hoje')).text()).toBe(HOJE);
    expect(w.get(daCarteira('sem-permissao')).text()).toBe(
      'Você pode ver estes ajustes, mas não mudar. Peça a um administrador da conta.'
    );
    expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
    expect(w.find(daCarteira('ajuste-onde')).exists()).toBe(false);
    expect(escolhas(w)).toHaveLength(0);
  });

  it('quem não tem as duas permissões também só lê', async () => {
    assento.ajusta = false;
    servidorResponde();

    const w = await abrir();

    expect(w.get(daCarteira('escolha-de-hoje')).text()).toBe(HOJE);
    expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
  });

  it('se a conta ainda não escolheu, diz isso', async () => {
    servidorResponde({ ajustes: SEM_ESCOLHA, semPermissao: true });

    const w = await abrir();

    expect(w.get(daCarteira('escolha-de-hoje')).text()).toBe(
      'Ninguém escolheu ainda em que funil as renovações ficam. Até lá, nenhuma renovação aparece.'
    );
  });
});

describe('carregando e erro', () => {
  it('no erro, diz a frase e tentar de novo carrega a tela', async () => {
    SegurosAPI.renovacoes.mockRejectedValueOnce(erroHttp(500));
    const w = await abrir();

    expect(w.get(daCarteira('erro')).text()).toContain(
      'Não consegui abrir os ajustes. Tente de novo.'
    );
    expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);

    servidorResponde();
    await clicar(w, `${daCarteira('erro')} button`);

    expect(w.find(daCarteira('erro')).exists()).toBe(false);
    expect(w.find(daCarteira('ajuste-onde')).exists()).toBe(true);
  });

  it('enquanto a resposta não chega, mostra o esqueleto e nenhum botão de salvar', async () => {
    SegurosAPI.renovacoes.mockReturnValue(new Promise(() => {}));

    const w = await abrir();

    expect(w.find(daCarteira('carregando')).exists()).toBe(true);
    expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
  });
});
