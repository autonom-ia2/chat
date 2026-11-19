import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { useI18n } from 'vue-i18n';
import { defineComponent } from 'vue';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import AcoesDaAba from '../../components/lista/AcoesDaAba.vue';
import BarraDeControles from '../../components/lista/BarraDeControles.vue';
import LinhaDePessoa from '../../components/lista/LinhaDePessoa.vue';
import {
  CAMPOS_DE_ORDEM,
  gruposDeOrdem,
  ordemDaPreferencia,
  preferenciaDaOrdem,
} from '../../lista/ordens';
import { camposRecusados } from '../../lista/recusaDoContato';
import { useOrdemGuardada } from '../../lista/useOrdemGuardada';
import {
  dadosDaPessoaNova,
  usePessoaNaGaveta,
} from '../../lista/usePessoaNaGaveta';

// #3062 — as peças novas da paridade com a lista de contatos de hoje: as sete
// ordens e a preferência que elas dividem com a lista antiga, a recusa de
// e-mail ou telefone repetido, a gaveta de criar e editar, e os botões novos.
const preferencias = vi.hoisted(() => ({ valores: {}, gravar: vi.fn() }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: {
      get value() {
        return preferencias.valores;
      },
    },
    updateUISettings: preferencias.gravar,
  }),
}));

withFullI18n('pt_BR');

const comT = () => {
  let t;
  mount(
    defineComponent({
      setup() {
        t = useI18n().t;
        return () => null;
      },
    })
  );
  return t;
};

const erro422 = attributes =>
  Object.assign(new Error('422'), {
    response: { status: 422, data: { attributes } },
  });

afterEach(() => {
  preferencias.valores = {};
  vi.resetAllMocks();
});

describe('ordens da aba Pessoas', () => {
  it('são as sete da lista de hoje, cada uma nos dois sentidos', () => {
    expect(CAMPOS_DE_ORDEM.map(({ chave }) => chave)).toEqual([
      'ULTIMA_CONVERSA',
      'NOME',
      'EMAIL',
      'EMPRESA',
      'CIDADE',
      'PAIS',
      'CHEGADA',
    ]);
    CAMPOS_DE_ORDEM.forEach(({ ordens }) => expect(ordens).toHaveLength(2));
  });

  it('cada ordem vai e volta pela preferência `contacts_sort_by` sem perder nada', () => {
    const valores = CAMPOS_DE_ORDEM.flatMap(({ ordens }) =>
      ordens.map(({ value }) => value)
    );
    const guardadas = valores.map(preferenciaDaOrdem);
    expect(new Set(guardadas).size).toBe(14);
    expect(guardadas.map(ordemDaPreferencia)).toEqual(valores);
  });

  it('lê a preferência que a lista de hoje grava, e a desconhecida abre pela última conversa', () => {
    expect(ordemDaPreferencia('-city')).toBe('cidade_z_a');
    expect(ordemDaPreferencia('name')).toBe('nome');
    expect(ordemDaPreferencia('phone_number')).toBe('ultima_conversa');
    expect(ordemDaPreferencia(undefined)).toBe('ultima_conversa');
    expect(preferenciaDaOrdem('inventada')).toBeNull();
  });

  it('no seletor, o campo é o grupo e o botão fechado diz campo e sentido', () => {
    const grupos = gruposDeOrdem(comT());
    expect(grupos.map(({ label }) => label)).toEqual([
      'Última conversa',
      'Nome',
      'E-mail',
      'Empresa',
      'Cidade',
      'País',
      'Quando chegou',
    ]);
    const cidade = grupos[4].options;
    expect(cidade.map(({ label }) => label)).toEqual(['De A a Z', 'De Z a A']);
    expect(cidade[1].shortLabel).toBe('Cidade, de Z a A');
  });
});

describe('useOrdemGuardada', () => {
  it('Pessoas abre na guardada; Empresas sempre pela última conversa', () => {
    preferencias.valores = { contacts_sort_by: 'email' };
    const { ordemDaAba } = useOrdemGuardada({ demo: false });
    expect(ordemDaAba('pessoas')).toBe('email_a_z');
    expect(ordemDaAba('empresas')).toBe('ultima_conversa');
  });

  it('grava só a ordem de Pessoas e nunca na demonstração', () => {
    useOrdemGuardada({ demo: false }).guardar('pais_z_a', 'pessoas');
    useOrdemGuardada({ demo: false }).guardar('nome', 'empresas');
    useOrdemGuardada({ demo: true }).guardar('nome', 'pessoas');
    expect(preferencias.gravar.mock.calls).toEqual([
      [{ contacts_sort_by: '-country' }],
    ]);
  });
});

describe('camposRecusados', () => {
  it('422 do contato com e-mail e telefone vira o aviso de cada campo', () => {
    expect(camposRecusados(erro422(['email', 'phone_number']))).toEqual({
      email: 'EMAIL_REPETIDO',
      telefone: 'TELEFONE_REPETIDO',
    });
  });

  it('outra recusa ou outro erro volta vazio', () => {
    expect(camposRecusados(erro422(['name']))).toEqual({});
    expect(camposRecusados({ response: { status: 500, data: {} } })).toEqual(
      {}
    );
    expect(camposRecusados(new Error('rede'))).toEqual({});
  });
});

describe('usePessoaNaGaveta', () => {
  const montar = acoes => {
    const avisos = { aoCriar: vi.fn(), aoSalvar: vi.fn(), aoFalhar: vi.fn() };
    return { gaveta: usePessoaNaGaveta({ acoes, ...avisos }), avisos };
  };

  it('a pessoa nova não leva campo vazio', () => {
    expect(
      dadosDaPessoaNova({
        name: 'Bia',
        additional_attributes: { city: '', company_name: 'Padaria' },
      })
    ).toEqual({
      name: 'Bia',
      additional_attributes: { company_name: 'Padaria' },
    });
  });

  it('nova pessoa: cria, fecha e entrega a criada', async () => {
    const criarPessoa = vi.fn().mockResolvedValue({ id: 9, name: 'Bia' });
    const { gaveta, avisos } = montar({ criarPessoa });
    gaveta.abrirNova();
    expect(gaveta.ehNova.value).toBe(true);
    await gaveta.salvar({ name: 'Bia' });
    expect(criarPessoa).toHaveBeenCalledWith({
      name: 'Bia',
      additional_attributes: {},
    });
    expect(gaveta.aberta.value).toBe(false);
    expect(avisos.aoCriar).toHaveBeenCalledWith({ id: 9, name: 'Bia' });
  });

  it('editar: salva pelo id da pessoa aberta e avisa com os dados', async () => {
    const salvarPessoa = vi.fn().mockResolvedValue({});
    const { gaveta, avisos } = montar({ salvarPessoa });
    gaveta.abrirEdicao({ id: 3, name: 'Ana' });
    expect(gaveta.ehNova.value).toBe(false);
    await gaveta.salvar({ name: 'Ana Maria' });
    expect(salvarPessoa).toHaveBeenCalledWith(3, { name: 'Ana Maria' });
    expect(avisos.aoSalvar).toHaveBeenCalledWith({ name: 'Ana Maria' });
  });

  it('repetido: fica aberta com o aviso do campo, sem aviso geral; reabrir limpa', async () => {
    const criarPessoa = vi.fn().mockRejectedValue(erro422(['email']));
    const { gaveta, avisos } = montar({ criarPessoa });
    gaveta.abrirNova();
    await gaveta.salvar({ name: 'Bia' });
    expect(gaveta.aberta.value).toBe(true);
    expect(gaveta.errosDoServidor.value).toEqual({ email: 'EMAIL_REPETIDO' });
    expect(avisos.aoFalhar).not.toHaveBeenCalled();
    gaveta.abrirNova();
    expect(gaveta.errosDoServidor.value).toEqual({});
  });

  it('outra falha: fica aberta e avisa dizendo se era nova', async () => {
    const salvarPessoa = vi.fn().mockRejectedValue(new Error('500'));
    const { gaveta, avisos } = montar({ salvarPessoa });
    gaveta.abrirEdicao({ id: 3 });
    await gaveta.salvar({ name: 'Ana' });
    expect(gaveta.aberta.value).toBe(true);
    expect(avisos.aoFalhar).toHaveBeenCalledWith(false);
  });

  it('clique duplo em salvar manda uma vez só', async () => {
    let soltar;
    const criarPessoa = vi.fn(
      () =>
        new Promise(resolve => {
          soltar = resolve;
        })
    );
    const { gaveta } = montar({ criarPessoa });
    gaveta.abrirNova();
    const primeiro = gaveta.salvar({ name: 'Bia' });
    await gaveta.salvar({ name: 'Bia' });
    soltar({ id: 1 });
    await primeiro;
    expect(criarPessoa).toHaveBeenCalledTimes(1);
  });
});

describe('BarraDeControles com as ordens agrupadas', () => {
  it('passa os grupos ao seletor e avisa a ordem escolhida', () => {
    const grupos = gruposDeOrdem(comT());
    const w = mount(BarraDeControles, {
      props: {
        ordem: 'ultima_conversa',
        placeholder: 'Buscar',
        gruposDeOrdem: grupos,
      },
    });
    const escolha = w.getComponent(ChoiceSelect);
    expect(escolha.props('groups')).toEqual(grupos);
    expect(escolha.props('options')).toEqual([]);
    escolha.vm.$emit('update:modelValue', 'empresa_z_a');
    expect(w.emitted('update:ordem')).toEqual([['empresa_z_a']]);
  });
});

describe('AcoesDaAba', () => {
  const montar = props => mount(AcoesDaAba, { props });

  it('com as duas: os botões com nome (sm em diante) e o menu "Ações" no celular', async () => {
    const w = montar({ podeCriar: true, podeBaixar: true });
    const nova = w.get('[data-relacionamentos="nova-pessoa"]');
    const baixar = w.get('[data-relacionamentos="baixar-planilha"]');
    expect(nova.text()).toBe('Nova pessoa');
    expect(baixar.text()).toBe('Baixar planilha');
    const botoes = nova.element.parentElement.classList;
    expect([botoes.contains('hidden'), botoes.contains('sm:flex')]).toEqual([
      true,
      true,
    ]);
    const celular = w.get('[data-relacionamentos="acoes-no-celular"]');
    expect(celular.classes()).toContain('sm:hidden');
    expect(celular.get('[aria-haspopup="menu"]').text()).toBe('Ações');
    await nova.trigger('click');
    await baixar.trigger('click');
    expect(w.emitted('criar')).toHaveLength(1);
    expect(w.emitted('baixar')).toHaveLength(1);
  });

  it('o menu do celular tem as duas, com nome, e cada uma avisa a sua', async () => {
    const w = montar({ podeCriar: true, podeBaixar: true });
    const celular = w.get('[data-relacionamentos="acoes-no-celular"]');
    await celular.get('[aria-haspopup="menu"]').trigger('click');
    expect(celular.findAll('[role="menuitem"]').map(i => i.text())).toEqual([
      'Nova pessoa',
      'Baixar planilha',
    ]);
    await celular.get('[data-acao="baixar"]').trigger('click');
    expect(w.emitted('baixar')).toHaveLength(1);
    expect(w.emitted('criar')).toBeUndefined();
  });

  it('com uma só, ela fica à vista também no celular, sem menu', () => {
    const w = montar({ podeCriar: true });
    expect(w.find('[data-relacionamentos="acoes-no-celular"]').exists()).toBe(
      false
    );
    expect(
      w.get('[data-relacionamentos="nova-pessoa"]').element.parentElement
        .classList
    ).not.toContain('hidden');
    expect(w.find('[data-relacionamentos="baixar-planilha"]').exists()).toBe(
      false
    );
  });
});

describe('LinhaDePessoa: o lápis de editar', () => {
  const ANA = {
    id: 1,
    name: 'Ana Albuquerino',
    phone_number: '+5511910310001',
    additional_attributes: {},
    labels: [],
  };

  it('quem pode editar vê o lápis com o nome da pessoa, e ele avisa', async () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: ANA, agora: Date.now(), podeEditar: true },
    });
    const lapis = w.get('[data-relacionamentos="editar"]');
    expect(lapis.attributes('aria-label')).toBe(
      'Alterar informações de Ana Albuquerino'
    );
    await lapis.trigger('click');
    expect(w.emitted('editar')).toHaveLength(1);
  });

  it('quem não pode não vê o lápis', () => {
    const w = mount(LinhaDePessoa, {
      props: { pessoa: ANA, agora: Date.now() },
    });
    expect(w.find('[data-relacionamentos="editar"]').exists()).toBe(false);
  });
});
