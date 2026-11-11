import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useAlert } from 'dashboard/composables';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { acoesDaListaFonte } from '../../fonte/acoesDaListaFonte';
import AbasDaLista from '../../components/lista/AbasDaLista.vue';
import BarraDeAcaoEmGrupo from '../../components/lista/BarraDeAcaoEmGrupo.vue';
import BarraDeControles from '../../components/lista/BarraDeControles.vue';
import CampoDeBusca from '../../components/lista/CampoDeBusca.vue';
import DialogoApagar from '../../components/lista/DialogoApagar.vue';
import DialogoCriarCards from '../../components/lista/DialogoCriarCards.vue';
import DialogoEtiqueta from '../../components/lista/DialogoEtiqueta.vue';
import DialogoMandarMensagem from '../../components/lista/DialogoMandarMensagem.vue';
import GavetaDeFiltros from '../../components/lista/GavetaDeFiltros.vue';
import HeroiDaLista from '../../components/lista/HeroiDaLista.vue';
import LinhaDeEmpresa from '../../components/lista/LinhaDeEmpresa.vue';
import LinhaDePessoa from '../../components/lista/LinhaDePessoa.vue';
import MostrarMais from '../../components/lista/MostrarMais.vue';

// As peças da lista de Relacionamentos (#2894), com o texto de verdade em pt_BR.
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/components-next/dialog/Dialog.vue', async () => ({
  default: (await import('./dialogoFalso')).DialogoFalso,
}));
vi.mock('dashboard/components-next/TeleportWithDirection.vue', async () => ({
  default: (await import('./dialogoFalso')).TeleportFalso,
}));

withFullI18n('pt_BR');

const AGORA = Date.now();
const diasAtras = dias => Math.floor(AGORA / 1000) - dias * 86400;
const pessoa = (extra = {}) => ({
  id: 1,
  name: 'Ana Albuquerino',
  phone_number: '+5511910310001',
  thumbnail: '',
  contact_type: 'lead',
  last_activity_at: diasAtras(3),
  opted_out_at: null,
  additional_attributes: { company_name: 'Padaria Brandolim' },
  ...extra,
});
const lote = (quantas, comoCada = () => ({})) =>
  Array.from({ length: quantas }, (_, i) =>
    pessoa({ id: i + 1, name: `Pessoa ${i + 1}`, ...comoCada(i) })
  );

afterEach(() => {
  vi.clearAllMocks();
});

// A fonte de demonstração espera num setTimeout (atraso 0): só um tempo de
// verdade deixa as respostas chegarem.
const assentar = async () => {
  await new Promise(resolve => {
    setTimeout(resolve, 30);
  });
  await flushPromises();
};

describe('HeroiDaLista', () => {
  const montar = resumo => mount(HeroiDaLista, { props: { resumo } });
  const frase = w => w.get('[data-heroi-frase]').text();

  it('quem sumiu: frase, botão principal e "trazer" discreto', async () => {
    const w = montar({ total: 280, clientes: 120, sumiu_1_a_3_meses: 42 });
    expect(frase(w)).toBe('42 pessoas não falam com você há mais de um mês.');
    const principal = w.get('[data-relacionamentos="heroi-acao"]');
    expect(principal.text()).toBe('Ver quem sumiu');
    await principal.trigger('click');
    expect(w.emitted('verGrupo')).toEqual([['sumiu_1_a_3_meses']]);
    await w.get('[data-relacionamentos="heroi-trazer"]').trigger('click');
    expect(w.emitted('trazer')).toHaveLength(1);
  });

  it('resumo: pessoas e clientes, e o botão leva aos clientes', async () => {
    const w = montar({ total: 280, clientes: 120, sumiu_1_a_3_meses: 0 });
    expect(frase(w)).toBe('Você tem 280 pessoas aqui. 120 já são clientes.');
    await w.get('[data-relacionamentos="heroi-acao"]').trigger('click');
    expect(w.emitted('verGrupo')).toEqual([['clientes']]);
  });

  it('conta vazia: o botão principal é "Trazer minha lista" e não há outro no canto', async () => {
    const w = montar({ total: 0, clientes: 0, sumiu_1_a_3_meses: 0 });
    expect(frase(w)).toBe('Traga as pessoas com quem você já fala.');
    expect(w.find('[data-relacionamentos="heroi-trazer"]').exists()).toBe(
      false
    );
    const principal = w.get('[data-relacionamentos="heroi-acao"]');
    expect(principal.text()).toBe('Trazer minha lista');
    await principal.trigger('click');
    expect(w.emitted('trazer')).toHaveLength(1);
  });

  it('usa o singular quando é uma pessoa só', () => {
    expect(frase(montar({ total: 1, clientes: 1, sumiu_1_a_3_meses: 0 }))).toBe(
      'Você tem 1 pessoa aqui. 1 já é cliente.'
    );
    expect(frase(montar({ total: 5, clientes: 1, sumiu_1_a_3_meses: 1 }))).toBe(
      '1 pessoa não fala com você há mais de um mês.'
    );
  });
});

describe('AbasDaLista', () => {
  it('marca a aba escolhida e deixa só ela na ordem do Tab', () => {
    const w = mount(AbasDaLista, { props: { modelValue: 'empresas' } });
    const abas = w.findAll('[role="tab"]');
    expect(abas.map(a => a.text())).toEqual(['Pessoas', 'Empresas']);
    expect(abas.map(a => a.attributes('aria-selected'))).toEqual([
      'false',
      'true',
    ]);
    expect(abas.map(a => a.attributes('tabindex'))).toEqual(['-1', '0']);
    expect(w.get('[role="tablist"]').attributes('aria-label')).toBe(
      'Pessoas ou empresas'
    );
  });

  it('troca de aba ao clicar', async () => {
    const w = mount(AbasDaLista, { props: { modelValue: 'pessoas' } });
    await w.get('[data-relacionamentos="aba-empresas"]').trigger('click');
    expect(w.emitted('update:modelValue')).toEqual([['empresas']]);
  });

  it.each([
    ['pessoas', 'ArrowRight', 'empresas'],
    ['empresas', 'ArrowLeft', 'pessoas'],
    ['empresas', 'ArrowRight', 'pessoas'],
    ['empresas', 'Home', 'pessoas'],
    ['pessoas', 'End', 'empresas'],
  ])('na aba %s, %s vai para %s', async (atual, tecla, destino) => {
    const w = mount(AbasDaLista, { props: { modelValue: atual } });
    await w.get('[role="tablist"]').trigger('keydown', { key: tecla });
    expect(w.emitted('update:modelValue')).toEqual([[destino]]);
  });

  it('ignora as outras teclas', async () => {
    const w = mount(AbasDaLista, { props: { modelValue: 'pessoas' } });
    await w.get('[role="tablist"]').trigger('keydown', { key: 'a' });
    expect(w.emitted('update:modelValue')).toBeUndefined();
  });
});

describe('CampoDeBusca', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  const montar = (props = {}) =>
    mount(CampoDeBusca, {
      props: { placeholder: 'Buscar por nome', ...props },
    });

  it('espera 300 ms depois da última letra para avisar', async () => {
    const w = montar();
    await w.get('input').setValue('an');
    await w.get('input').setValue('ana');
    vi.advanceTimersByTime(299);
    expect(w.emitted('update:modelValue')).toBeUndefined();
    vi.advanceTimersByTime(1);
    expect(w.emitted('update:modelValue')).toEqual([['ana']]);
  });

  it('Enter avisa na hora, uma vez só', async () => {
    const w = montar();
    await w.get('input').setValue('ana');
    await w.get('input').trigger('keydown', { key: 'Enter' });
    vi.advanceTimersByTime(1000);
    expect(w.emitted('update:modelValue')).toEqual([['ana']]);
  });

  it('o X limpa o campo e avisa na hora; sem texto, não há X', async () => {
    const w = montar({ modelValue: 'ana' });
    await w.get('button').trigger('click');
    expect(w.get('input').element.value).toBe('');
    expect(w.emitted('update:modelValue')).toEqual([['']]);
    expect(w.find('button').exists()).toBe(false);
  });

  it('esvazia o campo quando quem usa limpa a busca por fora', async () => {
    const w = montar({ modelValue: 'ana' });
    expect(w.get('input').element.value).toBe('ana');
    await w.setProps({ modelValue: '' });
    expect(w.get('input').element.value).toBe('');
  });

  it('põe o texto no placeholder e o marcador para o robô de print', () => {
    const w = montar();
    const campo = w.get('[data-relacionamentos="busca"]');
    expect(campo.attributes('placeholder')).toBe('Buscar por nome');
    expect(campo.attributes('aria-label')).toBe('Buscar');
  });
});

describe('BarraDeControles', () => {
  const montar = (props = {}) =>
    mount(BarraDeControles, {
      props: { ordem: 'ultima_conversa', placeholder: 'Buscar', ...props },
    });

  it('mostra "Mais filtros" e abre a gaveta', async () => {
    const w = montar();
    const botao = w.get('[data-relacionamentos="mais-filtros"]');
    expect(botao.text()).toBe('Mais filtros');
    await botao.trigger('click');
    expect(w.emitted('abrirFiltros')).toHaveLength(1);
  });

  it('mostra quantos filtros estão ativos no botão', () => {
    const w = montar({ filtrosAtivos: 2 });
    expect(w.get('[data-relacionamentos="mais-filtros"]').text()).toBe(
      'Mais filtros · 2'
    );
  });

  it('não tem "Mais filtros" na aba Empresas', () => {
    expect(
      montar({ comFiltros: false })
        .find('[data-relacionamentos="mais-filtros"]')
        .exists()
    ).toBe(false);
  });

  it('oferece as três ordens e avisa a escolhida', async () => {
    const w = montar();
    const escolha = w.getComponent(ChoiceSelect);
    expect(escolha.props('options').map(o => o.label)).toEqual([
      'Última conversa',
      'Nome',
      'Mais novos',
    ]);
    escolha.vm.$emit('update:modelValue', 'nome');
    expect(w.emitted('update:ordem')).toEqual([['nome']]);
  });
});

describe('LinhaDePessoa', () => {
  it('mostra nome, telefone, empresa e quando falou', () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: pessoa(), agora: AGORA },
    });
    expect(w.attributes('data-relacionamentos')).toBe('linha');
    expect(w.text()).toContain('Ana Albuquerino');
    expect(w.text()).toContain(
      '+55 11 91031-0001 · Padaria Brandolim · Falou há 3 dias'
    );
  });

  it('põe os selos Cliente e Não quer mensagens quando é o caso', () => {
    const w = mount(LinhaDePessoa, {
      props: {
        pessoa: pessoa({
          contact_type: 'customer',
          opted_out_at: diasAtras(5),
        }),
        agora: AGORA,
      },
    });
    expect(w.get('[data-selo="cliente"]').text()).toBe('Cliente');
    expect(w.get('[data-selo="alerta"]').text()).toBe('Não quer mensagens');
  });

  it('sem selo, sem telefone e sem empresa: "Sem telefone · Nunca conversou"', () => {
    const w = mount(LinhaDePessoa, {
      props: {
        pessoa: pessoa({
          phone_number: null,
          additional_attributes: {},
          last_activity_at: null,
        }),
        agora: AGORA,
      },
    });
    expect(w.find('[data-selo]').exists()).toBe(false);
    expect(w.text()).toContain('Sem telefone · Nunca conversou');
  });

  it('clicar no nome abre a ficha', async () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: pessoa(), agora: AGORA },
    });
    await w.get('button').trigger('click');
    expect(w.emitted('abrir')).toEqual([[expect.objectContaining({ id: 1 })]]);
  });

  it('a caixa de marcar marca e NÃO abre a ficha, e tem nome para o leitor de tela', async () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: pessoa(), agora: AGORA },
    });
    await w.get('[data-relacionamentos="marcar"] input').setValue(true);
    expect(w.emitted('alternar')).toHaveLength(1);
    expect(w.emitted('abrir')).toBeUndefined();
    expect(w.get('label').text()).toBe('Marcar Ana Albuquerino');
  });

  it('mostra a caixa marcada', () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: pessoa(), marcada: true, agora: AGORA },
    });
    expect(w.get('[data-relacionamentos="marcar"] input').element.checked).toBe(
      true
    );
  });

  it('tem "Conversar" no desktop e um ícone com nome no celular', async () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: pessoa(), agora: AGORA },
    });
    const botoes = w
      .findAll('button')
      .filter(b => b.text() === 'Conversar' || b.attributes('aria-label'));
    const [desktop, celular] = botoes;
    expect(desktop.classes()).toContain('sm:opacity-0');
    expect(desktop.classes()).toContain('group-focus-within:opacity-100');
    expect(celular.attributes('aria-label')).toBe(
      'Conversar com Ana Albuquerino'
    );
    expect(celular.classes()).toContain('sm:hidden');
    await desktop.trigger('click');
    await celular.trigger('click');
    expect(w.emitted('conversar')).toHaveLength(2);
    expect(w.emitted('abrir')).toBeUndefined();
  });
});

describe('LinhaDeEmpresa', () => {
  const empresa = (extra = {}) => ({
    id: 4,
    name: 'Padaria Brandolim',
    contacts_count: 3,
    customers_count: 1,
    last_activity_at: diasAtras(40),
    ...extra,
  });

  it('mostra nome, "3 pessoas", selo Cliente e a última conversa', () => {
    const w = mount(LinhaDeEmpresa, {
      props: { empresa: empresa(), agora: AGORA },
    });
    expect(w.text()).toContain('Padaria Brandolim');
    expect(w.text()).toContain('3 pessoas · Falou há 1 mês');
    expect(w.get('[data-selo="cliente"]').text()).toBe('Cliente');
  });

  it('sem cliente não há selo; com uma pessoa vale o singular', () => {
    const w = mount(LinhaDeEmpresa, {
      props: {
        empresa: empresa({
          customers_count: 0,
          contacts_count: 1,
          last_activity_at: null,
        }),
        agora: AGORA,
      },
    });
    expect(w.find('[data-selo]').exists()).toBe(false);
    expect(w.text()).toContain('1 pessoa · Nunca conversou');
  });

  it('diz "Ninguém ainda" quando não tem pessoas e abre a ficha ao clicar', async () => {
    const w = mount(LinhaDeEmpresa, {
      props: {
        empresa: empresa({ contacts_count: 0, customers_count: 0 }),
        agora: AGORA,
      },
    });
    expect(w.text()).toContain('Ninguém ainda');
    await w.get('button').trigger('click');
    expect(w.emitted('abrir')).toEqual([[expect.objectContaining({ id: 4 })]]);
  });
});

describe('MostrarMais', () => {
  it('diz "Mostrando 25 de 120" e pede mais', async () => {
    const w = mount(MostrarMais, {
      props: { mostradas: 25, total: 120, temMais: true },
    });
    expect(w.text()).toContain('Mostrando 25 de 120');
    await w.get('[data-relacionamentos="mostrar-mais"]').trigger('click');
    expect(w.emitted('mais')).toHaveLength(1);
  });

  it('sem mais, só a contagem', () => {
    const w = mount(MostrarMais, { props: { mostradas: 9, total: 9 } });
    expect(w.text()).toBe('Mostrando 9 de 9');
    expect(w.find('button').exists()).toBe(false);
  });
});

describe('BarraDeAcaoEmGrupo', () => {
  const montar = quantas =>
    mount(BarraDeAcaoEmGrupo, { props: { quantas }, attachTo: document.body });

  it('diz "12 marcadas" e a ação principal é Mandar mensagem', async () => {
    const w = montar(12);
    expect(w.get('p').text()).toBe('12 marcadas');
    expect(montar(1).get('p').text()).toBe('1 marcada');
    const principal = w.get('[data-relacionamentos="mandar-mensagem"]');
    expect(principal.text()).toBe('Mandar mensagem');
    await principal.trigger('click');
    expect(w.emitted('mandarMensagem')).toHaveLength(1);
    w.unmount();
  });

  it('Criar cards e Etiqueta saem da barra; fechar desmarca', async () => {
    const w = montar(3);
    await w.get('[data-relacionamentos="criar-cards"]').trigger('click');
    await w.get('[data-relacionamentos="etiqueta"]').trigger('click');
    await w.get('button[aria-label="Desmarcar todas"]').trigger('click');
    expect(w.emitted('criarCards')).toHaveLength(1);
    expect(w.emitted('etiqueta')).toHaveLength(1);
    expect(w.emitted('fechar')).toHaveLength(1);
    w.unmount();
  });

  it('o menu "⋯" abre, tem Apagar e fecha com Esc', async () => {
    const w = montar(3);
    const gatilho = w.get('[data-relacionamentos="mais-acoes"]');
    expect(gatilho.attributes('aria-expanded')).toBe('false');
    await gatilho.trigger('click');
    expect(gatilho.attributes('aria-expanded')).toBe('true');
    expect(w.get('[role="menu"]').isVisible()).toBe(true);
    await w.get('[role="menu"]').trigger('keydown', { key: 'Escape' });
    expect(gatilho.attributes('aria-expanded')).toBe('false');
    await gatilho.trigger('click');
    await w.get('[data-acao="apagar"]').trigger('click');
    expect(w.emitted('apagar')).toHaveLength(1);
    expect(gatilho.attributes('aria-expanded')).toBe('false');
    w.unmount();
  });

  it('no celular o menu também leva Criar cards e Etiqueta', async () => {
    const w = montar(3);
    await w.get('[data-relacionamentos="mais-acoes"]').trigger('click');
    const doCelular = w
      .findAll('[role="menuitem"]')
      .filter(i => i.classes().includes('sm:hidden'));
    expect(doCelular.map(i => i.attributes('data-acao'))).toEqual([
      'criarCards',
      'etiqueta',
    ]);
    await doCelular[0].trigger('click');
    expect(w.emitted('criarCards')).toHaveLength(1);
    w.unmount();
  });
});

describe('GavetaDeFiltros', () => {
  const opcoes = {
    empresas: [{ value: 7, label: 'Padaria Brandolim' }],
    etiquetas: [{ value: 'feira', label: 'feira' }],
    cidades: [{ value: 'Santos', label: 'Santos' }],
  };
  const montar = (props = {}) =>
    mount(GavetaDeFiltros, {
      props: { aberta: true, opcoes, ...props },
      attachTo: document.body,
    });

  it('fechada, não desenha nada', () => {
    const w = montar({ aberta: false });
    expect(w.find('[data-relacionamentos="gaveta-filtros"]').exists()).toBe(
      false
    );
    w.unmount();
  });

  it('aberta, é um diálogo com título e os quatro campos', () => {
    const w = montar();
    const gaveta = w.get('[data-relacionamentos="gaveta-filtros"]');
    expect(gaveta.attributes('role')).toBe('dialog');
    expect(gaveta.attributes('aria-modal')).toBe('true');
    expect(w.get('[data-view-title]').text()).toBe('Mais filtros');
    expect(w.findAll('label').map(l => l.text())).toEqual([
      'Empresa',
      'Etiqueta',
      'Cidade',
      'Chegou em',
    ]);
    w.unmount();
  });

  it('cada campo oferece "Todas" (ou "Qualquer data") e as opções da base', () => {
    const w = montar();
    const [empresa, , , chegou] = w.findAllComponents(ChoiceSelect);
    expect(empresa.props('options').map(o => o.label)).toEqual([
      'Todas',
      'Padaria Brandolim',
    ]);
    expect(chegou.props('options').map(o => o.label)).toEqual([
      'Qualquer data',
      'Nos últimos 7 dias',
      'Nos últimos 30 dias',
      'Nos últimos 90 dias',
    ]);
    w.unmount();
  });

  it('"Ver resultado" aplica o que foi escolhido', async () => {
    const w = montar();
    const [empresa, , cidade] = w.findAllComponents(ChoiceSelect);
    empresa.vm.$emit('update:modelValue', 7);
    cidade.vm.$emit('update:modelValue', 'Santos');
    await w.vm.$nextTick();
    const ver = w.findAll('button').find(b => b.text() === 'Ver resultado');
    await ver.trigger('click');
    expect(w.emitted('aplicar')).toEqual([
      [{ empresa: 7, etiqueta: '', cidade: 'Santos', chegouEm: '' }],
    ]);
    w.unmount();
  });

  it('começa com os filtros que já estão valendo', () => {
    const w = montar({
      filtros: { empresa: 7, etiqueta: '', cidade: '', chegouEm: '' },
    });
    expect(w.findAllComponents(ChoiceSelect)[0].props('modelValue')).toBe(7);
    w.unmount();
  });

  it('"Limpar" avisa para tirar todos, e Esc e o X fecham', async () => {
    const w = montar();
    await w
      .findAll('button')
      .find(b => b.text() === 'Limpar')
      .trigger('click');
    expect(w.emitted('limpar')).toHaveLength(1);
    await w.get('[role="dialog"]').trigger('keydown', { key: 'Escape' });
    await w.get('button[aria-label="Fechar"]').trigger('click');
    expect(w.emitted('fechar')).toHaveLength(2);
    w.unmount();
  });
});

describe('DialogoMandarMensagem', () => {
  const doBlocoA = () => [
    ...lote(10),
    pessoa({ id: 90, name: 'Quem pediu', opted_out_at: diasAtras(3) }),
    pessoa({ id: 91, name: 'Sem fone', phone_number: null }),
  ];
  const abrir = async pessoas => {
    const w = mount(DialogoMandarMensagem, { props: { pessoas } });
    w.vm.abrir();
    await w.vm.$nextTick();
    return w;
  };

  it('diz quantas recebem e quem fica de fora, com o motivo', async () => {
    const w = await abrir(doBlocoA());
    expect(w.get('[data-relacionamentos="dialogo-mensagem"]').text()).toBe(
      '10 pessoas vão receber. 2 ficam de fora: 1 pediu para não receber, 1 está sem telefone.'
    );
    expect(w.get('h3').text()).toBe('Mandar mensagem');
  });

  it('Continuar entrega a quantidade que recebe e fecha', async () => {
    const w = await abrir(doBlocoA());
    await w.get('[data-confirmar]').trigger('click');
    expect(w.emitted('continuar')).toEqual([[10]]);
    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
  });

  it('sem ninguém de fora, só diz quantos recebem (e usa o singular)', async () => {
    const w = await abrir(lote(1));
    expect(w.get('[data-relacionamentos="dialogo-mensagem"]').text()).toBe(
      '1 pessoa vai receber.'
    );
  });

  it('quando todo mundo fica de fora, avisa e não deixa continuar', async () => {
    const w = await abrir([pessoa({ opted_out_at: diasAtras(1) })]);
    expect(w.get('[data-relacionamentos="dialogo-mensagem"]').text()).toBe(
      'Ninguém vai receber. 1 fica de fora: 1 pediu para não receber.'
    );
    expect(w.get('[data-confirmar]').attributes('disabled')).toBeDefined();
  });
});

describe('DialogoCriarCards', () => {
  const montar = (pessoas = lote(12)) =>
    mount(DialogoCriarCards, {
      props: {
        pessoas,
        acoes: acoesDaListaFonte({ demo: 'cheio', atraso: 0 }),
      },
    });
  const abrir = async w => {
    w.vm.abrir();
    await assentar();
  };

  it('pergunta funil e etapa, com o primeiro de cada já escolhido', async () => {
    const w = montar();
    await abrir(w);
    const [funil, etapa] = w.findAllComponents(ChoiceSelect);
    expect(w.findAll('label').map(l => l.text())).toEqual([
      'Em qual funil?',
      'Em qual etapa?',
    ]);
    expect(funil.props('modelValue')).toBe('vendas');
    expect(etapa.props('modelValue')).toBe('primeira-conversa');
    expect(w.get('[data-confirmar]').text()).toBe('Criar 12 cards');
  });

  it('trocar o funil escolhe a primeira etapa dele', async () => {
    const w = montar();
    await abrir(w);
    w.findAllComponents(ChoiceSelect)[0].vm.$emit(
      'update:modelValue',
      'depois-da-compra'
    );
    await w.vm.$nextTick();
    const [, etapa] = w.findAllComponents(ChoiceSelect);
    expect(etapa.props('modelValue')).toBe('boas-vindas');
    expect(etapa.props('options').map(o => o.label)).toEqual([
      'Boas-vindas',
      'Acompanhando',
    ]);
  });

  it('depois de criar, diz quantos cards e quem ficou de fora, com o motivo', async () => {
    const w = montar(lote(12));
    await abrir(w);
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    const resultado = w.get('[data-relacionamentos="dialogo-cards"]').text();
    expect(resultado).toContain('11 cards criados.');
    expect(resultado).toContain('Ficaram de fora:');
    expect(resultado).toContain('Pessoa 9 · Já tem um card neste funil');
    expect(w.find('[data-cancelar]').exists()).toBe(false);
    expect(w.get('[data-confirmar]').text()).toBe('Pronto');
  });

  it('sem ninguém de fora, não mostra a lista; "Pronto" fecha e avisa que concluiu', async () => {
    const w = montar(lote(2));
    await abrir(w);
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    const resultado = w.get('[data-relacionamentos="dialogo-cards"]').text();
    expect(resultado).toBe('2 cards criados.');
    await w.get('[data-confirmar]').trigger('click');
    expect(w.emitted('concluido')).toHaveLength(1);
  });

  it('cancelar antes de criar não avisa que concluiu', async () => {
    const w = montar();
    await abrir(w);
    await w.get('[data-cancelar]').trigger('click');
    expect(w.emitted('concluido')).toBeUndefined();
  });

  it('se a fonte falha ao criar, avisa e continua no diálogo', async () => {
    const acoes = {
      ...acoesDaListaFonte({ demo: 'cheio', atraso: 0 }),
      criarCards: vi.fn().mockRejectedValue(new Error('x')),
    };
    const w = mount(DialogoCriarCards, { props: { pessoas: lote(2), acoes } });
    await abrir(w);
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui criar os cards. Tente de novo.'
    );
    expect(w.get('[data-relacionamentos="dialogo-cards"]').text()).toContain(
      'Em qual funil?'
    );
  });

  it('se a fonte falha ao abrir, avisa e não abre', async () => {
    const acoes = { funis: vi.fn().mockRejectedValue(new Error('x')) };
    const w = mount(DialogoCriarCards, { props: { pessoas: lote(2), acoes } });
    await abrir(w);
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui carregar. Tente de novo.'
    );
    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
  });
});

describe('DialogoEtiqueta', () => {
  const montar = (pessoas = lote(3)) =>
    mount(DialogoEtiqueta, {
      props: {
        pessoas,
        acoes: acoesDaListaFonte({ demo: 'cheio', atraso: 0 }),
      },
    });
  const abrir = async w => {
    w.vm.abrir();
    await assentar();
  };

  it('só deixa colocar depois de escolher uma etiqueta', async () => {
    const w = montar();
    await abrir(w);
    expect(w.get('[data-confirmar]').attributes('disabled')).toBeDefined();
    expect(w.get('label').text()).toBe('Qual etiqueta?');
    w.getComponent(ChoiceSelect).vm.$emit('update:modelValue', 'feira');
    await w.vm.$nextTick();
    expect(w.get('[data-confirmar]').attributes('disabled')).toBeUndefined();
  });

  it('coloca a etiqueta, avisa com a contagem, fecha e conclui', async () => {
    const w = montar();
    await abrir(w);
    w.getComponent(ChoiceSelect).vm.$emit('update:modelValue', 'feira');
    await w.vm.$nextTick();
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(useAlert).toHaveBeenCalledWith(
      'Etiqueta “feira” colocada em 3 pessoas.'
    );
    expect(w.emitted('concluido')).toHaveLength(1);
    expect(w.find('[data-dialogo-falso]').exists()).toBe(false);
  });

  it('se a fonte falha, avisa e não conclui', async () => {
    const acoes = {
      etiquetas: async () => ['feira'],
      aplicarEtiqueta: vi.fn().mockRejectedValue(new Error('x')),
    };
    const w = mount(DialogoEtiqueta, { props: { pessoas: lote(1), acoes } });
    await abrir(w);
    w.getComponent(ChoiceSelect).vm.$emit('update:modelValue', 'feira');
    await w.vm.$nextTick();
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(useAlert).toHaveBeenCalledWith(
      'Não consegui colocar a etiqueta. Tente de novo.'
    );
    expect(w.emitted('concluido')).toBeUndefined();
  });
});

describe('DialogoApagar', () => {
  const montar = (pessoas = lote(12)) =>
    mount(DialogoApagar, {
      props: {
        pessoas,
        acoes: acoesDaListaFonte({ demo: 'cheio', atraso: 0 }),
      },
    });

  it('pergunta "Apagar 12 pessoas?" e avisa "Isto não volta."', async () => {
    const w = montar();
    w.vm.abrir();
    await w.vm.$nextTick();
    expect(w.get('h3').text()).toBe('Apagar 12 pessoas?');
    expect(w.get('p').text()).toBe('Isto não volta.');
    expect(w.get('[data-confirmar]').text()).toBe('Apagar');
  });

  it('não fecha ao tocar fora e usa o singular para uma pessoa', async () => {
    const w = montar(lote(1));
    w.vm.abrir();
    await w.vm.$nextTick();
    expect(w.get('[data-dialogo-falso]').attributes('data-fechar-fora')).toBe(
      'false'
    );
    expect(w.get('[data-dialogo-falso]').attributes('data-tipo')).toBe('alert');
    expect(w.get('h3').text()).toBe('Apagar 1 pessoa?');
  });

  it('apaga (simulado), avisa e conclui', async () => {
    const w = montar(lote(2));
    w.vm.abrir();
    await w.vm.$nextTick();
    await w.get('[data-confirmar]').trigger('click');
    await assentar();
    expect(useAlert).toHaveBeenCalledWith('2 pessoas apagadas.');
    expect(w.emitted('concluido')).toHaveLength(1);
  });
});
