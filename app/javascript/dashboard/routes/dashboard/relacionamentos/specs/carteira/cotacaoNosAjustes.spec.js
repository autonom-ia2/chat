import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import SegurosAPI from 'dashboard/api/relacionamentosSeguros';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AjustarRenovacoesPage from '../../pages/AjustarRenovacoesPage.vue';
import { usarDemo } from '../../fonte/modoDemo';
import { assentar, daCarteira, erroHttp } from './apoio';

// "Cotação da renovação" em "Ajustar renovações" (#2901, E8), com o texto de
// verdade em pt_BR: quem faz a cotação, como a proposta sai, quem responde o
// cliente e por qual WhatsApp; só "Ninguém" sem o Agente de Cotação; o aviso
// quando o agente vai responder e não está no WhatsApp escolhido; as
// cotações do mês. O cliente de API é de mentira e os dados são inventados
// (o agente da demonstração se chama Nina).
vi.mock('dashboard/api/relacionamentosSeguros', () => ({
  default: {
    renovacoes: vi.fn(),
    salvarRenovacoes: vi.fn(),
    cotacoes: vi.fn(),
  },
}));
vi.mock('../../fonte/modoDemo', async importOriginal => ({
  ...(await importOriginal()),
  usarDemo: vi.fn(() => null),
}));
const conta = vi.hoisted(() => ({ carteira_seguros: true }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: conta } }),
}));
vi.mock('../../carteira/usePodeAjustarRenovacoes', async () => {
  const { computed } = await import('vue');
  return { usePodeAjustarRenovacoes: () => computed(() => true) };
});
vi.mock('vue-router', async () => {
  const { reactive } = await import('vue');
  const rota = reactive({ query: {}, params: {} });
  const roteador = { push: vi.fn(), replace: vi.fn() };
  return { useRoute: () => rota, useRouter: () => roteador };
});

withFullI18n('pt_BR');
vi.setConfig({ testTimeout: 30000 });

const FUNIS = [
  { id: 1, nome: 'Renovação', etapas: [{ id: 11, nome: 'A vencer' }] },
];
const CAIXAS = [
  { id: 5, nome: 'WhatsApp da loja', liaLigada: true },
  { id: 6, nome: 'WhatsApp do plantão', liaLigada: false },
];
const ESCOLHAS = {
  funilId: 1,
  etapaId: 11,
  dias: 60,
  quemCota: 'ninguem',
  quemEnvia: 'pessoa',
  quemResponde: 'equipe',
  caixaId: null,
};
// O que o servidor manda em `GET seguros/renovacoes` com a chave da cotação.
const doServidor = (mudancas = {}) => ({
  ajustes: ESCOLHAS,
  escolha: 'feita',
  funis: FUNIS,
  vencimentos: [3, 20],
  semPermissao: false,
  aggerLigado: true,
  cotaSozinha: true,
  cotaSemConversa: false,
  agente: 'Nina',
  cotacaoLiberada: true,
  caixas: CAIXAS,
  ...mudancas,
});
const servidorResponde = mudancas =>
  SegurosAPI.renovacoes.mockResolvedValue({ data: doServidor(mudancas) });
const servidorGuarda = () =>
  SegurosAPI.salvarRenovacoes.mockImplementation(async ajustes => ({
    data: ajustes,
  }));

let aberta;
const abrir = async () => {
  usarDemo.mockReturnValue(null);
  aberta = mount(AjustarRenovacoesPage, {
    attachTo: document.body,
    global: { stubs: { transition: true } },
  });
  await assentar();
  return aberta;
};
const escolhaEm = (w, marca) =>
  w.get(daCarteira(marca)).findComponent(ChoiceSelect);
const escolher = async (w, marca, valor) => {
  escolhaEm(w, marca).vm.$emit('update:modelValue', valor);
  await assentar();
};
const salvar = async w => {
  await w.get(daCarteira('salvar-ajustes')).trigger('click');
  await assentar();
};
const cartao = w => w.find(daCarteira('ajuste-cotacao'));
const rotulos = (w, marca) =>
  escolhaEm(w, marca)
    .props('options')
    .map(opcao => opcao.label);

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
  SegurosAPI.renovacoes.mockReset();
  SegurosAPI.salvarRenovacoes.mockReset();
  SegurosAPI.cotacoes.mockReset();
  SegurosAPI.cotacoes.mockResolvedValue({
    data: {
      inicio: '2026-11-01',
      fim: '2026-11-17',
      cotacoes: 7,
      seguradorasAcionadas: 30,
      seguradorasComPreco: 12,
      daRenovacao: 4,
    },
  });
});
afterEach(() => {
  vi.useRealTimers();
  aberta?.unmount();
  aberta = null;
});

describe('sem a chave da cotação na conta', () => {
  it('a tela é a da E5: sem o cartão e sem ler as cotações do mês', async () => {
    SegurosAPI.renovacoes.mockResolvedValue({
      data: {
        ajustes: { funilId: 1, etapaId: 11, dias: 60 },
        escolha: 'feita',
        funis: FUNIS,
        vencimentos: [],
        semPermissao: false,
        aggerLigado: false,
        cotaSozinha: false,
        cotaSemConversa: false,
        agente: null,
      },
    });
    servidorGuarda();

    const w = await abrir();
    expect(cartao(w).exists()).toBe(false);
    expect(SegurosAPI.cotacoes).not.toHaveBeenCalled();

    await w.get(`${daCarteira('dias-antes')} input`).setValue('45');
    await assentar();
    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      funilId: 1,
      etapaId: 11,
      dias: 45,
    });
  });
});

describe('as três escolhas e o WhatsApp', () => {
  it('com "Ninguém", só a pergunta de quem cota; o robô abre as outras três', async () => {
    servidorResponde();

    const w = await abrir();

    expect(cartao(w).get('h2').text()).toBe('Cotação da renovação');
    expect(rotulos(w, 'escolher-quem-cota')).toEqual([
      'Ninguém, cotação manual',
      'O robô cota sozinho',
      'O robô cota e Nina responde',
    ]);
    expect(w.find(daCarteira('escolher-quem-envia')).exists()).toBe(false);
    expect(w.find(daCarteira('escolher-caixa')).exists()).toBe(false);

    await escolher(w, 'escolher-quem-cota', 'robo');

    expect(rotulos(w, 'escolher-quem-envia')).toEqual([
      'Uma pessoa confere e aperta Enviar',
      'Sai sozinha',
    ]);
    expect(rotulos(w, 'escolher-quem-responde')).toEqual(['A equipe', 'Nina']);
    expect(rotulos(w, 'escolher-caixa')).toEqual([
      'WhatsApp da loja',
      'WhatsApp do plantão',
    ]);
    expect(w.findAll('select')).toHaveLength(0);
  });

  it('salva as quatro escolhas junto com o resto dos ajustes', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();

    await escolher(w, 'escolher-quem-cota', 'lia');
    await escolher(w, 'escolher-quem-envia', 'sozinho');
    await escolher(w, 'escolher-quem-responde', 'lia');
    await escolher(w, 'escolher-caixa', 5);
    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith({
      funilId: 1,
      etapaId: 11,
      dias: 60,
      quemCota: 'lia',
      quemEnvia: 'sozinho',
      quemResponde: 'lia',
      caixaId: 5,
    });
    expect(w.get(daCarteira('ajustes-salvos')).text()).toBe('Ajustes salvos.');
  });

  it('"Sai sozinha" diz em uma linha que ninguém confere antes', async () => {
    servidorResponde({ ajustes: { ...ESCOLHAS, quemCota: 'robo' } });
    const w = await abrir();

    expect(w.get(daCarteira('apoio-do-envio')).text()).toContain(
      'só vai ao cliente quando alguém clicar em Enviar proposta'
    );

    await escolher(w, 'escolher-quem-envia', 'sozinho');

    expect(w.get(daCarteira('apoio-do-envio')).text()).toBe(
      'A proposta vai para o cliente assim que fica pronta, sem ninguém conferir antes.'
    );
  });

  it('o robô sem WhatsApp escolhido não salva: diz o que falta', async () => {
    servidorResponde();
    servidorGuarda();
    const w = await abrir();

    await escolher(w, 'escolher-quem-cota', 'robo');
    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
    expect(w.get(daCarteira('alerta-dos-ajustes')).text()).toBe(
      'Escolha por qual WhatsApp o robô fala com o cliente.'
    );
    expect(escolhaEm(w, 'escolher-caixa').props('invalid')).toBe(true);
  });

  it('a recusa do servidor vira frase de leigo e a tela relê a conta', async () => {
    servidorResponde();
    SegurosAPI.salvarRenovacoes.mockRejectedValue(
      erroHttp(422, { error: 'caixa_invalida' })
    );
    const w = await abrir();

    await escolher(w, 'escolher-quem-cota', 'robo');
    await escolher(w, 'escolher-caixa', 6);
    await salvar(w);

    expect(w.get(daCarteira('alerta-dos-ajustes')).text()).toBe(
      'Esse WhatsApp não serve mais para a cotação. Atualizei a tela: escolha outro WhatsApp e salve.'
    );
    expect(w.text()).not.toContain('caixa_invalida');
    expect(SegurosAPI.renovacoes).toHaveBeenCalledTimes(2);
  });
});

describe('a conta que não pode pôr o robô para cotar', () => {
  it.each([
    [{ cotaSozinha: false, agente: null }, 'SEM_AGENTE', 'Agente de Cotação'],
    [{ caixas: [] }, 'SEM_CAIXA', 'WhatsApp oficial'],
  ])(
    'só "Ninguém" aparece, com a frase do porquê (%#)',
    async (mudancas, motivo, frase) => {
      servidorResponde(mudancas);

      const w = await abrir();

      const so = w.get(daCarteira('cotacao-so-ninguem'));
      expect(so.attributes('data-motivo')).toBe(motivo);
      expect(so.text()).toContain('Ninguém, cotação manual');
      expect(so.text()).toContain(frase);
      expect(w.find(daCarteira('escolher-quem-cota')).exists()).toBe(false);
      expect(w.text()).not.toContain('O robô cota sozinho');
      expect(cartao(w).findAll('button[disabled]')).toHaveLength(0);
    }
  );

  it('se o robô cotava, o rascunho volta para "Ninguém" e o salvar manda isso', async () => {
    servidorResponde({
      cotaSozinha: false,
      agente: null,
      ajustes: { ...ESCOLHAS, quemCota: 'robo', caixaId: 5 },
    });
    servidorGuarda();
    const w = await abrir();

    await salvar(w);

    expect(SegurosAPI.salvarRenovacoes).toHaveBeenCalledWith(
      expect.objectContaining({ quemCota: 'ninguem' })
    );
  });
});

describe('o aviso do agente fora do WhatsApp', () => {
  it('aparece antes de salvar quando o agente responde e não está na caixa', async () => {
    servidorResponde({ ajustes: { ...ESCOLHAS, quemCota: 'robo' } });
    const w = await abrir();

    await escolher(w, 'escolher-quem-responde', 'lia');
    await escolher(w, 'escolher-caixa', 6);

    const aviso = w.get(daCarteira('aviso-do-agente'));
    expect(aviso.text()).toContain(
      'Nina não está no WhatsApp WhatsApp do plantão'
    );
    expect(aviso.text()).toContain('Agentes');
    expect(SegurosAPI.salvarRenovacoes).not.toHaveBeenCalled();
  });

  it('não aparece com a caixa em que o agente está, nem com a equipe respondendo', async () => {
    servidorResponde({ ajustes: { ...ESCOLHAS, quemCota: 'robo' } });
    const w = await abrir();

    await escolher(w, 'escolher-quem-responde', 'lia');
    await escolher(w, 'escolher-caixa', 5);
    expect(w.find(daCarteira('aviso-do-agente')).exists()).toBe(false);

    await escolher(w, 'escolher-quem-responde', 'equipe');
    await escolher(w, 'escolher-caixa', 6);
    expect(w.find(daCarteira('aviso-do-agente')).exists()).toBe(false);
  });
});

describe('as cotações do mês', () => {
  it('mostra só as contagens, sem dinheiro', async () => {
    servidorResponde();

    const w = await abrir();

    const consumo = w.get(daCarteira('consumo-de-cotacoes'));
    expect(consumo.text()).toContain('Cotações neste mês: 7');
    expect(consumo.text()).toContain('Seguradoras com preço: 12');
    expect(consumo.text()).not.toContain('R$');
  });

  it('se as contagens não vêm, o resto do cartão continua', async () => {
    servidorResponde();
    SegurosAPI.cotacoes.mockRejectedValue(erroHttp(500));

    const w = await abrir();

    expect(w.find(daCarteira('consumo-de-cotacoes')).exists()).toBe(false);
    expect(w.find(daCarteira('escolher-quem-cota')).exists()).toBe(true);
  });
});
