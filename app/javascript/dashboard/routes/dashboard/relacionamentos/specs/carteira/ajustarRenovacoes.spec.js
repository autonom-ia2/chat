import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useRouter } from 'vue-router';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AjustarRenovacoesPage from '../../pages/AjustarRenovacoesPage.vue';
import { FUNIL_PAROU, funilParou } from '../../carteira/funilDasRenovacoes';
import { esquecerAjustesDaDemo } from '../../demo/carteiraAjustes';
import { usarDemo } from '../../fonte/modoDemo';
import {
  DialogoFalso,
  assentar,
  carregarDemonstracao,
  daCarteira,
  erroHttp,
} from './apoio';

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
// #3057 — "Criar o funil de renovações para mim": o caminho do CRM
// (carteira/useCriarFunilDeRenovacoes.js, com o próprio teste) é de mentira
// aqui; cada teste diz se quem olha pode criar funil e o que a criação devolve.
const criacao = vi.hoisted(() => ({ podeCriar: false, criar: null }));
vi.mock('../../carteira/useCriarFunilDeRenovacoes', async () => {
  const { computed, ref } = await import('vue');
  return {
    FUNIL_INCOMPLETO: 'FunilIncompleto',
    useCriarFunilDeRenovacoes: () => {
      const criando = ref(false);
      return {
        podeCriar: computed(() => criacao.podeCriar),
        criando,
        criar: async () => {
          criando.value = true;
          try {
            return await criacao.criar();
          } finally {
            criando.value = false;
          }
        },
      };
    },
  };
});
// O sinal de que o funil escolhido parou de servir tem um leitor só
// (carteira/funilDasRenovacoes.js): cada estado é testado trocando o que ele lê.
vi.mock('../../carteira/funilDasRenovacoes', async importOriginal => ({
  ...(await importOriginal()),
  funilParou: vi.fn(() => ''),
}));
// A guarda de saída da tela (onBeforeRouteLeave) fica guardada para o teste
// chamar como o roteador chamaria.
const saida = vi.hoisted(() => ({ guarda: null }));
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = { push: vi.fn(), replace: vi.fn() };
  return {
    useRoute: () => rota,
    useRouter: () => roteador,
    onBeforeRouteLeave: guarda => {
      saida.guarda = guarda;
    },
  };
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

// A largura da tela, para o que muda no celular (useMediaQuery).
const larguraDaTela = larga => {
  window.matchMedia = vi.fn().mockImplementation(consulta => ({
    matches: larga,
    media: consulta,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
    addListener: vi.fn(),
    removeListener: vi.fn(),
  }));
};

let aberta;
const abrir = async ({ demo = null } = {}) => {
  usarDemo.mockReturnValue(demo);
  aberta = mount(AjustarRenovacoesPage, {
    attachTo: document.body,
    global: { stubs: { transition: true, Dialog: DialogoFalso } },
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
  criacao.podeCriar = false;
  criacao.criar = vi.fn();
  funilParou.mockReset();
  funilParou.mockReturnValue('');
  SegurosAPI.renovacoes.mockReset();
  SegurosAPI.salvarRenovacoes.mockReset();
  roteador.push.mockClear();
  roteador.replace.mockClear();
});
afterEach(() => {
  vi.useRealTimers();
  delete window.matchMedia;
  saida.guarda = null;
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
    // Quem não pode criar funil no CRM não ganha o botão de criar.
    expect(w.find(daCarteira('criar-funil')).exists()).toBe(false);

    await clicar(w, daCarteira('abrir-crm'));

    expect(roteador.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
  });
});

// #3057 — a conta sem funil não manda mais a pessoa ao CRM para voltar depois:
// quem pode criar funil ganha o funil de renovações pronto, já escolhido.
describe('conta sem funil, para quem pode criar funil', () => {
  const FUNIL_NOVO = {
    id: 9,
    nome: 'Renovação',
    etapas: [
      { id: 91, nome: 'A vencer' },
      { id: 92, nome: 'Cotando' },
    ],
  };
  const semFunilEDepoisONovo = () => {
    SegurosAPI.renovacoes
      .mockResolvedValueOnce({
        data: doServidor({ ajustes: SEM_ESCOLHA, funis: [] }),
      })
      .mockResolvedValue({
        data: doServidor({ ajustes: SEM_ESCOLHA, funis: [FUNIL_NOVO] }),
      });
  };
  beforeEach(() => {
    criacao.podeCriar = true;
  });

  it('oferece criar o funil em azul, e "Abrir o CRM" vira um link ao lado', async () => {
    larguraDaTela(true);
    servidorResponde({ ajustes: SEM_ESCOLHA, funis: [] });
    const w = await abrir();

    expect(w.get(daCarteira('sem-funil')).text()).toContain(
      'Sua conta ainda não tem um funil. Funil é o quadro do CRM onde cada renovação vira um cartão. Eu crio um pronto para você.'
    );
    expect(w.get(daCarteira('criar-funil')).text()).toBe(
      'Criar o funil de renovações para mim'
    );
    expect(w.get(daCarteira('abrir-crm')).text()).toBe('Abrir o CRM');
    expect(w.findAll('button[disabled]')).toHaveLength(0);

    await clicar(w, daCarteira('abrir-crm'));

    expect(roteador.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
    expect(criacao.criar).not.toHaveBeenCalled();
  });

  it('criado, o funil e a primeira etapa ficam escolhidos, e falta só salvar', async () => {
    semFunilEDepoisONovo();
    criacao.criar.mockResolvedValue({ id: 9, name: 'Renovação' });
    servidorGuarda();
    const w = await abrir();

    await clicar(w, daCarteira('criar-funil'));

    expect(criacao.criar).toHaveBeenCalledTimes(1);
    expect(w.get(daCarteira('funil-criado')).text()).toBe(
      'Criei o funil Renovação e já deixei escolhido. Falta tocar em Salvar ajustes, lá embaixo.'
    );
    expect(escolhas(w)[0].props('modelValue')).toBe(9);
    expect(escolhas(w)[1].props('modelValue')).toBe(91);
    expect(document.activeElement.id.endsWith('-funil')).toBe(true);
    // Nada foi guardado ainda: quem guarda é o Salvar.
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
    expect(w.find(daCarteira('ajuste-dias')).exists()).toBe(true);

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...SEM_ESCOLHA,
      funilId: 9,
      etapaId: 91,
    });
    expect(salvos(w)).toBe('Ajustes salvos.');
    expect(w.find(daCarteira('funil-criado')).exists()).toBe(false);
  });

  it('mexer em outra escolha tira o recado do funil criado', async () => {
    semFunilEDepoisONovo();
    criacao.criar.mockResolvedValue({ id: 9, name: 'Renovação' });
    const w = await abrir();
    await clicar(w, daCarteira('criar-funil'));

    await escolher(escolhas(w)[1], 92);

    expect(w.find(daCarteira('funil-criado')).exists()).toBe(false);
  });

  it('não criou: diz para tentar de novo e relê o que a conta tem', async () => {
    servidorResponde({ ajustes: SEM_ESCOLHA, funis: [] });
    criacao.criar.mockRejectedValue(erroHttp(500));
    const w = await abrir();

    await clicar(w, daCarteira('criar-funil'));

    expect(w.get(daCarteira('funil-nao-criado')).text()).toBe(
      'Não consegui criar o funil. Tente de novo.'
    );
    expect(w.get(daCarteira('funil-nao-criado')).attributes('role')).toBe(
      'alert'
    );
    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(2);
    expect(w.find(daCarteira('criar-funil')).exists()).toBe(true);
  });
  it('no celular o botão tem o texto curto, que cabe inteiro', async () => {
    larguraDaTela(false);
    servidorResponde({ ajustes: SEM_ESCOLHA, funis: [] });
    const w = await abrir();

    expect(w.get(daCarteira('criar-funil')).text()).toBe(
      'Criar o funil para mim'
    );
  });

  it('o funil nasceu mas faltou etapa: manda conferir no CRM, sem "tente de novo", e deixa o funil escolhido', async () => {
    semFunilEDepoisONovo();
    criacao.criar.mockRejectedValue(
      Object.assign(new Error('FunilIncompleto'), {
        name: 'FunilIncompleto',
        funil: { id: 9, name: 'Renovação' },
      })
    );
    const w = await abrir();

    await clicar(w, daCarteira('criar-funil'));

    const recado = w.get(daCarteira('funil-nao-criado'));
    expect(recado.text()).toBe(
      'O funil Renovação foi criado. Confira as etapas no CRM.'
    );
    expect(recado.text()).not.toContain('Tente de novo');
    expect(recado.attributes('role')).toBe('alert');
    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(2);
    expect(escolhas(w)[0].props('modelValue')).toBe(9);
    expect(escolhas(w)[1].props('modelValue')).toBe(91);
    expect(w.find(daCarteira('funil-criado')).exists()).toBe(false);
  });

  // Revisão: criou o funil mas a releitura falhou. A tela não recarrega (o
  // que apagaria o recado e o que a pessoa mexeu): fica e diz o que fazer.
  it('criou mas não releu: fica na tela e manda escolher o funil na lista', async () => {
    SegurosAPI.renovacoes
      .mockResolvedValueOnce({
        data: doServidor({ ajustes: SEM_ESCOLHA, funis: [] }),
      })
      .mockRejectedValue(new Error('500'));
    criacao.criar.mockRejectedValue(
      Object.assign(new Error('FunilIncompleto'), {
        name: 'FunilIncompleto',
        funil: { id: 9, name: 'Renovação' },
      })
    );
    const w = await abrir();

    await clicar(w, daCarteira('criar-funil'));

    expect(w.get(daCarteira('funil-nao-criado')).text()).toBe(
      'Criei o funil Renovação, mas não consegui deixá-lo escolhido. Escolha o funil Renovação na lista.'
    );
    expect(w.find(daCarteira('erro')).exists()).toBe(false);
    expect(w.find(daCarteira('sem-funil')).exists()).toBe(true);
  });
});

// #3057 — sair da tela com algo não salvo pergunta antes. A tela não salva
// sozinha: "Salvar ajustes" é um toque da pessoa.
describe('sair sem salvar', () => {
  const DESTINO = { name: 'relationships_home', query: { aba: 'seguros' } };
  const mudarOsDias = async w => {
    await escreverDias(w, '45');
  };

  it('sem nada mudado, sai direto', async () => {
    servidorResponde();
    await abrir();

    expect(saida.guarda(DESTINO)).toBe(true);
  });

  it('com algo mudado, não sai e pergunta, com as duas saídas', async () => {
    servidorResponde();
    const w = await abrir();
    await mudarOsDias(w);

    expect(saida.guarda(DESTINO)).toBe(false);
    await assentar();

    const pergunta = w.get(daCarteira('sair-dos-ajustes'));
    expect(pergunta.text()).toContain('Sair sem salvar?');
    expect(pergunta.text()).toContain(
      'As renovações só começam a aparecer depois de salvar.'
    );
    expect(w.get(daCarteira('salvar-e-sair')).text()).toBe('Salvar ajustes');
    expect(w.get(daCarteira('sair-sem-salvar')).text()).toBe('Sair sem salvar');
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
  });

  it('"Sair sem salvar" segue para onde ia, sem guardar nada', async () => {
    servidorResponde();
    const w = await abrir();
    await mudarOsDias(w);
    saida.guarda(DESTINO);
    await assentar();

    // O roteador de verdade chama a guarda durante o push.
    let passouNaGuarda;
    roteador.push.mockImplementationOnce(async destino => {
      passouNaGuarda = saida.guarda(destino);
    });

    await clicar(w, daCarteira('sair-sem-salvar'));

    expect(roteador.push).toHaveBeenCalledWith(DESTINO);
    expect(passouNaGuarda).toBe(true);
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
  });

  it('depois de sair (ou da navegação falhar), a guarda volta a perguntar', async () => {
    servidorResponde();
    const w = await abrir();
    await mudarOsDias(w);
    saida.guarda(DESTINO);
    await assentar();
    // vue-router devolve a falha (navegação cancelada) em vez de rejeitar.
    roteador.push.mockResolvedValueOnce({ type: 4 });

    await clicar(w, daCarteira('sair-sem-salvar'));
    await assentar();

    expect(saida.guarda(DESTINO)).toBe(false);
  });

  // Revisão: fechar a aba ou recarregar com algo não salvo também pergunta
  // (o navegador mostra a pergunta dele).
  it('fechar a aba com algo mudado pede ao navegador que pergunte; sem nada mudado, não', async () => {
    servidorResponde();
    const w = await abrir();
    const fecharAAba = () => {
      const evento = new Event('beforeunload', { cancelable: true });
      window.dispatchEvent(evento);
      return evento.defaultPrevented;
    };

    expect(fecharAAba()).toBe(false);
    await mudarOsDias(w);
    expect(fecharAAba()).toBe(true);
  });

  it('"Salvar ajustes" guarda e segue para onde ia', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();
    await mudarOsDias(w);
    saida.guarda(DESTINO);
    await assentar();

    await clicar(w, daCarteira('salvar-e-sair'));

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      ...ESCOLHAS,
      dias: 45,
    });
    expect(roteador.push).toHaveBeenCalledWith(DESTINO);
  });

  it('"Salvar ajustes" com algo faltando fica na tela e diz o que falta', async () => {
    servidorResponde();
    const w = await abrir();
    await escreverDias(w, '0');
    saida.guarda(DESTINO);
    await assentar();

    await clicar(w, daCarteira('salvar-e-sair'));

    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
    expect(roteador.push).not.toHaveBeenCalled();
    expect(w.find(daCarteira('sair-dos-ajustes')).exists()).toBe(false);
    expect(temAlerta(w)).toBe(true);
  });
});

// O funil pode existir sem etapa nenhuma (a criação do funil e a das etapas são
// pedidos separados): sem tratar isso a pessoa fica sem saída, com o Salvar
// pedindo uma etapa que não há.
describe('o funil escolhido que não tem etapa', () => {
  const COM_UM_VAZIO = [...FUNIS, { id: 3, nome: 'Novo', etapas: [] }];
  const SEM_ETAPA =
    'Esse funil não tem etapa para a renovação entrar. Escolha outro funil ou crie uma etapa nele no CRM.';
  const abrirEEscolherOVazio = async () => {
    servidorResponde({ ajustes: SEM_ESCOLHA, funis: COM_UM_VAZIO });
    const w = await abrir();
    await escolher(escolhas(w)[0], 3);
    return w;
  };

  it('diz que o funil não tem etapa e oferece o CRM, sem escolha vazia', async () => {
    const w = await abrirEEscolherOVazio();

    expect(w.get(daCarteira('funil-sem-etapa')).text()).toContain(
      'Esse funil ainda não tem etapa. Escolha outro funil, ou crie uma etapa nele no CRM e volte aqui.'
    );
    expect(escolhas(w)).toHaveLength(1);
    expect(w.findAll('button[disabled]')).toHaveLength(0);

    await clicar(w, daCarteira('abrir-crm'));

    expect(roteador.push).toHaveBeenCalledWith({ name: 'crm_kanban_index' });
  });

  it('Salvar pede outro funil (e não a etapa), marca o funil e não vai ao servidor', async () => {
    const w = await abrirEEscolherOVazio();

    await salvar(w);

    expect(alerta(w)).toBe(SEM_ETAPA);
    expect(escolhas(w)[0].props('invalid')).toBe(true);
    expect(document.activeElement?.id).toBe(escolhas(w)[0].props('triggerId'));
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
  });

  it('escolher um funil com etapa tira o aviso, e Salvar guarda', async () => {
    servidorGuarda();
    const w = await abrirEEscolherOVazio();
    await salvar(w);

    await escolher(escolhas(w)[0], 2);

    expect(temAlerta(w)).toBe(false);
    expect(w.find(daCarteira('funil-sem-etapa')).exists()).toBe(false);

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      funilId: 2,
      etapaId: 21,
      dias: 60,
      mensagens: 'mandar',
    });
    expect(salvos(w)).toBe('Ajustes salvos.');
  });
});

// O funil que a conta escolheu foi arquivado, ou o funil (ou a etapa) foi
// apagado: as renovações param de aparecer. A tela diz isso no topo do cartão
// do funil e pede outro.
describe.each([
  {
    estado: FUNIL_PAROU.ARQUIVADO,
    // O servidor ainda guarda a escolha, e o funil pode até continuar na lista.
    resposta: { ajustes: ESCOLHAS },
    aviso:
      'O funil das renovações foi arquivado. Escolha outro para as renovações voltarem a aparecer.',
    paraQuemLe:
      'O funil das renovações foi arquivado. Até alguém escolher outro, nenhuma renovação aparece.',
  },
  {
    estado: FUNIL_PAROU.APAGADO,
    resposta: { ajustes: SEM_ESCOLHA },
    aviso:
      'O funil ou a etapa das renovações não existe mais. Escolha outro funil para as renovações voltarem a aparecer.',
    paraQuemLe:
      'O funil ou a etapa das renovações não existe mais. Até alguém escolher outro funil, nenhuma renovação aparece.',
  },
])(
  'o funil das renovações parou de servir: $estado',
  ({ estado, resposta, aviso, paraQuemLe }) => {
    const abrirParado = async (mudancas = {}) => {
      funilParou.mockReturnValue(estado);
      servidorResponde({ ...resposta, ...mudancas });
      return abrir();
    };
    const avisoDoFunil = w => w.find(daCarteira('funil-parou'));

    it('o aviso fica no topo do cartão do funil, logo abaixo do título', async () => {
      const w = await abrirParado();

      const cartao = w.get(daCarteira('ajuste-onde'));
      expect(avisoDoFunil(w).text()).toBe(aviso);
      expect(avisoDoFunil(w).attributes('role')).toBe('alert');
      expect(avisoDoFunil(w).attributes('data-estado')).toBe(estado);
      expect(cartao.element.children[1]).toBe(avisoDoFunil(w).element);
      expect(w.text()).toContain(
        'Escolha em que funil as renovações ficam. Até lá, nenhuma renovação aparece.'
      );
    });

    it('o leitor recebe a resposta do servidor inteira', async () => {
      await abrirParado();

      expect(funilParou).toHaveBeenCalledWith(
        expect.objectContaining({ funis: FUNIS, vencimentos: [3, 20, 61] })
      );
    });

    it('o funil volta a ser uma escolha em aberto, sem botão desligado', async () => {
      const w = await abrirParado();

      expect(escolhas(w)).toHaveLength(1);
      expect(escolhas(w)[0].props('modelValue')).toBeNull();
      expect(w.findAll('button[disabled]')).toHaveLength(0);
      expect(w.find(daCarteira('ajuste-dias')).exists()).toBe(true);
      expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(true);
    });

    it('Salvar sem escolher outro funil pede o funil e não vai ao servidor', async () => {
      const w = await abrirParado();

      await salvar(w);

      expect(alerta(w)).toBe('Escolha o funil em que as renovações ficam.');
      expect(escolhas(w)[0].props('invalid')).toBe(true);
      expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
      expect(avisoDoFunil(w).exists()).toBe(true);
    });

    it('escolher outro funil e salvar guarda a escolha e tira o aviso', async () => {
      servidorGuarda();
      const w = await abrirParado();

      await escolher(escolhas(w)[0], 2);
      await salvar(w);

      expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
        funilId: 2,
        etapaId: 21,
        dias: 60,
        mensagens: 'mandar',
      });
      expect(salvos(w)).toBe('Ajustes salvos.');
      expect(avisoDoFunil(w).exists()).toBe(false);
    });

    it('quem só lê fica sabendo que as renovações pararam', async () => {
      const w = await abrirParado({ semPermissao: true });

      expect(w.get(daCarteira('escolha-de-hoje')).text()).toBe(paraQuemLe);
      expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
      expect(w.findAll('button[disabled]')).toHaveLength(0);
    });
  }
);

describe('o funil das renovações que serve', () => {
  it('sem o sinal do servidor, o cartão do funil não tem aviso', async () => {
    servidorResponde();

    const w = await abrir();

    expect(w.find(daCarteira('funil-parou')).exists()).toBe(false);
    expect(escolhas(w)[0].props('modelValue')).toBe(1);
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

  // O segundo clique chega com o primeiro pedido ainda a caminho.
  it('dois cliques seguidos em Salvar mandam um pedido só, e o "salvo" não vira alerta', async () => {
    servidorResponde();
    let responder;
    SegurosAPI.salvarRenovacoes.mockReturnValue(
      new Promise(resolve => {
        responder = resolve;
      })
    );
    const w = await abrir();
    await escreverDias(w, '45');
    const botao = w.get(daCarteira('salvar-ajustes'));

    botao.trigger('click');
    await botao.trigger('click');

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledTimes(1);
    expect(botao.attributes('disabled')).toBeUndefined();
    expect(temAlerta(w)).toBe(false);

    responder({ data: { ...ESCOLHAS, dias: 45 } });
    await assentar();

    expect(salvos(w)).toBe('Ajustes salvos.');
    expect(temAlerta(w)).toBe(false);
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

// 401 ou 403 ao ler os ajustes: "tente de novo" nunca resolveria.
describe('quem o servidor não deixa nem ler', () => {
  it.each([401, 403])(
    'com %i, diz que não tem acesso e oferece voltar, sem "tentar de novo"',
    async status => {
      SegurosAPI.renovacoes.mockRejectedValue(erroHttp(status));

      const w = await abrir();

      const semAcesso = w.get(daCarteira('ajustes-sem-acesso'));
      expect(semAcesso.text()).toContain(
        'Você não tem acesso aos ajustes das renovações. Peça a um administrador da conta.'
      );
      expect(w.find(daCarteira('erro')).exists()).toBe(false);
      expect(w.text()).not.toContain('Tente de novo');
      expect(w.find(daCarteira('salvar-ajustes')).exists()).toBe(false);
      expect(w.findAll('button[disabled]')).toHaveLength(0);

      await clicar(w, `${daCarteira('ajustes-sem-acesso')} button`);

      expect(roteador.push).toHaveBeenCalledWith({
        name: 'relationships_home',
        query: { aba: 'seguros' },
      });
      expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(1);
    }
  );
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
