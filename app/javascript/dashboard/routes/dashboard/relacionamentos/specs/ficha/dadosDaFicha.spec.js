import { flushPromises, mount } from '@vue/test-utils';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import GavetaDeInformacoes from '../../components/ficha/GavetaDeInformacoes.vue';
import ListaDeInformacoes from '../../components/ficha/ListaDeInformacoes.vue';
import CorpoDaFichaDaPessoa from '../../components/ficha/CorpoDaFichaDaPessoa.vue';

// #3075 — os dados que a ficha antiga tinha, na ficha nova e na gaveta:
// empresa cadastrada, país, "Sobre a pessoa", foto, campos personalizados com
// o tipo de cada um e a visão de quem só pode ver.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (chave, valores) =>
      valores ? `${chave} ${JSON.stringify(valores)}` : chave,
    locale: { value: 'pt_BR' },
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

// Endereço que roda código no clique: nunca pode virar link. Montado em partes
// para não ser um link de verdade dentro do teste.
const LINK_PERIGOSO = ['javascript', 'alert(1)'].join(':');

const stubs = {
  TeleportWithDirection: { template: '<div><slot /></div>' },
  Dialog: {
    template: '<div data-dialog><slot /><slot name="footer" /></div>',
    methods: { open() {}, close() {} },
  },
};

const definicao = (id, chave, tipo, extra) => ({
  id,
  attribute_model: 'contact_attribute',
  attribute_key: chave,
  attribute_display_name: `Campo ${chave}`,
  attribute_display_type: tipo,
  attribute_values: [],
  ...extra,
});
const DEFINICOES = [
  definicao(1, 'aniversario', 'date'),
  definicao(2, 'site', 'link'),
  definicao(3, 'filhos', 'number'),
  definicao(4, 'plano', 'list', { attribute_values: ['Prata', 'Ouro'] }),
  definicao(5, 'vip', 'checkbox'),
  definicao(6, 'apelido', 'text'),
];

const pessoa = (extra = {}) => ({
  id: 7,
  name: 'Ana Albuquerino',
  email: 'ana@exemplo.com.br',
  phone_number: '+5511900001007',
  thumbnail: 'https://exemplo.com.br/ana.png',
  company_id: 3,
  additional_attributes: {
    city: 'Santos',
    company_name: 'Padaria Dornelaz',
    social_profiles: {},
  },
  custom_attributes: {
    cpf: '52998224725',
    aniversario: '1990-05-12',
    filhos: 2,
    vip: true,
  },
  ...extra,
});

const marca = nome => `[data-relacionamentos="${nome}"]`;
const salvar = async w => {
  await w.get(marca('salvar-informacoes')).trigger('click');
  return w.emitted('salvar').at(-1)[0];
};

describe('gaveta: campos personalizados com o tipo de cada um', () => {
  const montar = props =>
    mount(GavetaDeInformacoes, {
      props: {
        aberta: true,
        pessoa: pessoa(),
        definicoes: DEFINICOES,
        escolhidos: [4],
        ...props,
      },
      attachTo: document.body,
      global: { stubs },
    });

  it('cada tipo tem o seu controle, com o nome que a conta deu', () => {
    const w = montar();
    const campo = chave => w.get(`[data-atributo="${chave}"]`);
    expect(campo('aniversario').get('input').attributes('type')).toBe('date');
    expect(campo('aniversario').get('input').element.value).toBe('1990-05-12');
    expect(campo('filhos').get('input').attributes('type')).toBe('number');
    expect(campo('site').get('input').attributes('type')).toBe('url');
    expect(campo('plano').findComponent(ChoiceSelect).exists()).toBe(true);
    expect(campo('vip').findComponent(ChoiceSelect).props('options')).toEqual([
      { value: true, label: 'RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.SIM' },
      { value: false, label: 'RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.NAO' },
    ]);
    expect(campo('plano').text()).toContain('Campo plano');
    // Sem <select> nativo.
    expect(w.find('select').exists()).toBe(false);
  });

  it('os campos vêm logo depois do nome, antes do telefone, em "Seus campos"', () => {
    const w = montar();
    const quadro = w.get(marca('campos-da-conta'));
    expect(quadro.get('h3').text()).toBe('RELACIONAMENTOS_FICHA.CAMPOS.TITULO');
    const nome = w.get('[data-foco]').element;
    const telefone = w.get('input[type="tel"]').element;
    // Na ordem do documento: quem vem antes na lista de todos os elementos.
    const antes = (a, b) => {
      const todos = [...document.querySelectorAll('*')];
      return todos.indexOf(a) < todos.indexOf(b);
    };
    expect(antes(nome, quadro.element)).toBe(true);
    expect(antes(quadro.element, telefone)).toBe(true);
    w.unmount();
  });

  it('os campos sem valor e fora da ficha ficam atrás de "Mais campos"', async () => {
    const w = montar();
    const botao = w.get(marca('mais-campos'));
    expect(botao.attributes('aria-expanded')).toBe('false');
    const painel = w.get(`#${botao.attributes('aria-controls')}`);
    // Escolhido pelo configurador (plano) ou com valor: à vista.
    expect(painel.find('[data-atributo="plano"]').exists()).toBe(false);
    expect(painel.find('[data-atributo="filhos"]').exists()).toBe(false);
    expect(painel.find('[data-atributo="site"]').exists()).toBe(true);
    expect(painel.find('[data-atributo="apelido"]').exists()).toBe(true);
    expect(painel.isVisible()).toBe(false);
    await botao.trigger('click');
    expect(painel.isVisible()).toBe(true);
  });

  it('número sobe como número; o que ninguém mexeu não vai', async () => {
    const w = montar();
    await w.get('[data-atributo="filhos"] input').setValue('3');
    const pedido = await salvar(w);
    expect(pedido.contato.custom_attributes).toEqual({ filhos: 3 });
    expect(pedido.apagar).toEqual([]);
  });

  it('"Limpar" esvazia a escolha, diz o que acontece e "Voltar como estava" desfaz', async () => {
    const w = montar();
    const vip = w.get('[data-atributo="vip"]');
    expect(vip.get(marca('limpar-atributo')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.LIMPAR'
    );
    await vip.get(marca('limpar-atributo')).trigger('click');
    expect(vip.get(marca('ajuda-do-campo')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.VAI_SAIR'
    );
    expect(vip.find(marca('limpar-atributo')).exists()).toBe(false);
    await vip.get(marca('voltar-atributo')).trigger('click');
    expect(vip.find(marca('ajuda-do-campo')).exists()).toBe(false);
    expect((await salvar(w)).apagar).toEqual([]);
    await vip.get(marca('limpar-atributo')).trigger('click');
    const pedido = await salvar(w);
    expect(pedido.apagar).toEqual(['vip']);
    expect(pedido.contato.custom_attributes).toEqual({});
  });

  it('campo de escrever não tem "Limpar": apagar o texto basta, e o aviso aparece', async () => {
    const w = montar();
    const filhos = w.get('[data-atributo="filhos"]');
    expect(filhos.find(marca('limpar-atributo')).exists()).toBe(false);
    await filhos.get('input').setValue('');
    expect(filhos.get(marca('ajuda-do-campo')).exists()).toBe(true);
    expect(filhos.find(marca('voltar-atributo')).exists()).toBe(true);
    expect((await salvar(w)).apagar).toEqual(['filhos']);
  });

  it('número que o navegador não lê não apaga o valor', async () => {
    const w = montar();
    const campo = w.get('[data-atributo="filhos"] input');
    Object.defineProperty(campo.element, 'validity', {
      value: { badInput: true },
      configurable: true,
    });
    await campo.setValue('');
    expect(
      w
        .find(
          '[data-atributo="filhos"] [data-relacionamentos="ajuda-do-campo"]'
        )
        .exists()
    ).toBe(false);
    const pedido = await salvar(w);
    expect(pedido.apagar).toEqual([]);
    expect(pedido.contato.custom_attributes).toEqual({});
  });

  it('data gravada em outro formato aparece como está, sem sumir', async () => {
    const w = montar({
      pessoa: pessoa({
        custom_attributes: { cpf: '52998224725', aniversario: '12/05/1990' },
      }),
    });
    const campo = w.get('[data-atributo="aniversario"] input');
    expect(campo.attributes('type')).toBe('text');
    expect(campo.element.value).toBe('12/05/1990');
    const pedido = await salvar(w);
    expect(pedido.apagar).toEqual([]);
    expect(pedido.contato.custom_attributes).toEqual({});
  });

  it('a escolha da lista e o "não" do sim-ou-não gravam', async () => {
    const w = montar();
    w.get('[data-atributo="plano"]')
      .getComponent(ChoiceSelect)
      .vm.$emit('update:modelValue', 'Ouro');
    w.get('[data-atributo="vip"]')
      .getComponent(ChoiceSelect)
      .vm.$emit('update:modelValue', false);
    await flushPromises();
    const pedido = await salvar(w);
    expect(pedido.contato.custom_attributes).toEqual({
      plano: 'Ouro',
      vip: false,
    });
  });

  it('link sem "https://" é aceito e vai completo; o que não é site não salva', async () => {
    const w = montar();
    await w.get(marca('mais-campos')).trigger('click');
    const campo = w.get('[data-atributo="site"] input');
    expect(campo.attributes('placeholder')).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.ATRIBUTO.LINK_EXEMPLO'
    );
    await campo.setValue('padaria bom dia');
    await w.get(marca('salvar-informacoes')).trigger('click');
    expect(w.emitted('salvar')).toBeUndefined();
    expect(w.get('[data-atributo="site"]').text()).toContain(
      'RELACIONAMENTOS_FICHA.GAVETA.ERRO.LINK'
    );
    await campo.setValue('ana.com.br');
    const pedido = await salvar(w);
    expect(pedido.contato.custom_attributes).toEqual({
      site: 'https://ana.com.br',
    });
  });

  it('"Mais campos" abre sozinho quando um campo de lá tem erro', async () => {
    const w = montar();
    const botao = w.get(marca('mais-campos'));
    await botao.trigger('click');
    await w.get('[data-atributo="site"] input').setValue('padaria bom dia');
    await botao.trigger('click');
    const painel = w.get(`#${botao.attributes('aria-controls')}`);
    expect(painel.isVisible()).toBe(false);
    await w.get(marca('salvar-informacoes')).trigger('click');
    expect(painel.isVisible()).toBe(true);
    expect(botao.attributes('aria-expanded')).toBe('true');
  });
});

describe('gaveta: empresa cadastrada', () => {
  const EMPRESAS = [
    { id: 3, nome: 'Padaria Dornelaz' },
    { id: 9, nome: 'Oficina do Bruno' },
  ];
  const montar = props =>
    mount(GavetaDeInformacoes, {
      props: {
        aberta: true,
        pessoa: pessoa(),
        comEmpresas: true,
        buscarEmpresas: vi.fn(async termo =>
          EMPRESAS.filter(item => item.nome.toLowerCase().includes(termo))
        ),
        ...props,
      },
      attachTo: document.body,
      global: { stubs },
    });
  const procurar = async (w, termo) => {
    const busca = w.get(marca('busca-da-empresa'));
    await busca.setValue(termo);
    await busca.trigger('keydown', { key: 'Enter' });
    await flushPromises();
  };

  it('mostra a empresa ligada com Trocar e Tirar', () => {
    const w = montar();
    const escolhida = w.get(marca('empresa-escolhida'));
    expect(escolhida.text()).toContain('Padaria Dornelaz');
    expect(w.find(marca('trocar-empresa')).exists()).toBe(true);
    expect(w.find(marca('tirar-empresa')).exists()).toBe(true);
    expect(w.find(marca('busca-da-empresa')).exists()).toBe(false);
  });

  it('Trocar procura entre as empresas da conta e a escolhida vai pelo id', async () => {
    const w = montar();
    await w.get(marca('trocar-empresa')).trigger('click');
    await procurar(w, 'oficina');
    await w.get('[data-empresa="9"]').trigger('click');
    expect(w.get(marca('empresa-escolhida')).text()).toContain(
      'Oficina do Bruno'
    );
    const pedido = await salvar(w);
    expect(pedido.contato.company_id).toBe(9);
    expect(pedido.contato.additional_attributes.company_name).toBe(
      'Oficina do Bruno'
    );
    expect(pedido.empresaNova).toBeNull();
  });

  it('nome que não existe vira "Cadastrar como empresa nova", gravada no Salvar', async () => {
    const w = montar({ pessoa: pessoa({ company_id: null }) });
    await w.get(marca('tirar-empresa')).trigger('click');
    await procurar(w, 'quitanda');
    expect(w.text()).toContain('NENHUMA');
    await w.get(marca('cadastrar-empresa')).trigger('click');
    expect(w.get(marca('empresa-escolhida')).text()).toContain(
      'EMPRESA_ESCOLHA.NOVA'
    );
    const pedido = await salvar(w);
    expect(pedido.empresaNova).toBe('quitanda');
    expect(pedido.contato).not.toHaveProperty('company_id');
  });

  it('o nome já cadastrado não oferece cadastrar de novo', async () => {
    const w = montar();
    await w.get(marca('trocar-empresa')).trigger('click');
    await procurar(w, 'padaria dornelaz');
    expect(w.find(marca('cadastrar-empresa')).exists()).toBe(false);
  });

  it('Tirar diz o que acontece e manda a pessoa sem empresa', async () => {
    const w = montar();
    await w.get(marca('tirar-empresa')).trigger('click');
    expect(w.get(marca('escolha-da-empresa')).text()).toContain(
      'EMPRESA_ESCOLHA.VAI_SAIR'
    );
    const pedido = await salvar(w);
    expect(pedido.contato.company_id).toBeNull();
    expect(pedido.contato.additional_attributes.company_name).toBe('');
  });

  it('a ficha que só tem o nome escrito pode ser ligada à empresa cadastrada', async () => {
    const w = montar({ pessoa: pessoa({ company_id: null }) });
    expect(w.get(marca('empresa-escolhida')).text()).toContain(
      'EMPRESA_ESCOLHA.SO_NOME'
    );
    await w.get(marca('trocar-empresa')).trigger('click');
    await flushPromises();
    expect(w.get(marca('busca-da-empresa')).element.value).toBe(
      'Padaria Dornelaz'
    );
  });

  it('nome escrito e não escolhido não salva: o erro diz o que fazer e a busca recebe o foco', async () => {
    const w = montar();
    await w.get(marca('tirar-empresa')).trigger('click');
    await procurar(w, 'oficina');
    await w.get(marca('salvar-informacoes')).trigger('click');
    await flushPromises();
    expect(w.emitted('salvar')).toBeUndefined();
    expect(w.get(marca('erro-da-empresa')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.ERRO.EMPRESA_SEM_ESCOLHA'
    );
    expect(document.activeElement).toBe(
      w.get(marca('busca-da-empresa')).element
    );
    await w.get('[data-empresa="9"]').trigger('click');
    expect(w.find(marca('erro-da-empresa')).exists()).toBe(false);
    expect((await salvar(w)).contato.company_id).toBe(9);
  });

  it('depois de Tirar, "Manter" devolve a empresa de quando a gaveta abriu', async () => {
    const w = montar();
    await w.get(marca('tirar-empresa')).trigger('click');
    const manter = w.get(marca('cancelar-troca-de-empresa'));
    expect(manter.text()).toContain('EMPRESA_ESCOLHA.MANTER');
    expect(manter.text()).toContain('Padaria Dornelaz');
    await manter.trigger('click');
    expect(w.get(marca('empresa-escolhida')).text()).toContain(
      'Padaria Dornelaz'
    );
    const pedido = await salvar(w);
    expect(pedido.contato).not.toHaveProperty('company_id');
  });

  it('a empresa nova já cadastrada numa tentativa anterior não é cadastrada de novo', async () => {
    const w = montar({ pessoa: pessoa({ company_id: null }) });
    await w.get(marca('tirar-empresa')).trigger('click');
    await procurar(w, 'quitanda');
    await w.get(marca('cadastrar-empresa')).trigger('click');
    await w.setProps({ empresaCadastrada: { id: 40, nome: 'quitanda' } });
    const pedido = await salvar(w);
    expect(pedido.empresaNova).toBeNull();
    expect(pedido.contato.company_id).toBe(40);
  });

  it('sem a chave `companies`, a empresa é o nome escrito, como antes', async () => {
    const w = montar({ comEmpresas: false });
    expect(w.find(marca('escolha-da-empresa')).exists()).toBe(false);
    const campo = w
      .findAll('label')
      .find(l => l.text() === 'RELACIONAMENTOS_FICHA.GAVETA.EMPRESA');
    await w.get(`#${campo.attributes('for')}`).setValue('Quitanda');
    const pedido = await salvar(w);
    expect(pedido.contato.additional_attributes.company_name).toBe('Quitanda');
    expect(pedido.contato).not.toHaveProperty('company_id');
  });
});

describe('gaveta: foto, país e "Sobre a pessoa"', () => {
  beforeEach(() => {
    URL.createObjectURL = vi.fn(() => 'blob:previa');
    URL.revokeObjectURL = vi.fn();
  });
  const montar = props =>
    mount(GavetaDeInformacoes, {
      props: { aberta: true, pessoa: pessoa(), ...props },
      attachTo: document.body,
      global: { stubs },
    });
  const escolherArquivo = async (w, arquivo) => {
    const campo = w.get('[data-relacionamentos="foto-da-pessoa"] input');
    Object.defineProperty(campo.element, 'files', {
      value: [arquivo],
      configurable: true,
    });
    await campo.trigger('change');
  };

  it('foto nova: prévia, o aviso de quando entra, e vai no Salvar', async () => {
    const w = montar();
    const arquivo = new File(['x'], 'ana.png', { type: 'image/png' });
    await escolherArquivo(w, arquivo);
    expect(w.get(marca('aviso-da-foto')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.FOTO.VAI_ENTRAR'
    );
    const pedido = await salvar(w);
    expect(pedido.foto).toEqual({ arquivo, previa: 'blob:previa' });
  });

  it('arquivo que não é foto não entra e diz o que fazer', async () => {
    const w = montar();
    await escolherArquivo(
      w,
      new File(['x'], 'nota.pdf', { type: 'application/pdf' })
    );
    expect(w.get(marca('erro-da-foto')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.FOTO.ERRO_TIPO'
    );
    expect((await salvar(w)).foto).toBeNull();
  });

  it('a prévia da foto escolhida é solta ao remover ou voltar como estava', async () => {
    const w = montar();
    await escolherArquivo(w, new File(['x'], 'a.png', { type: 'image/png' }));
    await w.get(marca('tirar-foto')).trigger('click');
    expect(URL.revokeObjectURL).toHaveBeenCalledWith('blob:previa');
    expect(w.find(marca('tirar-foto')).exists()).toBe(false);
  });

  it('Remover foto diz que sai ao salvar; "Voltar como estava" desfaz', async () => {
    const w = montar();
    expect(w.get(marca('tirar-foto')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.FOTO.TIRAR'
    );
    await w.get(marca('tirar-foto')).trigger('click');
    expect(w.get(marca('aviso-da-foto')).text()).toBe(
      'RELACIONAMENTOS_FICHA.GAVETA.FOTO.VAI_SAIR'
    );
    expect((await salvar(w)).foto).toEqual({ tirar: true });
    await w.get(marca('manter-foto')).trigger('click');
    expect((await salvar(w)).foto).toBeNull();
  });

  it('"Sobre a pessoa" explica o que vai ali e o que vai em Notas', () => {
    const w = montar();
    const campo = w.get(marca('sobre-a-pessoa')).element.closest('div');
    expect(campo.textContent).toContain(
      'RELACIONAMENTOS_FICHA.GAVETA.SOBRE_AJUDA'
    );
  });

  it('país pela escolha da casa e "Sobre a pessoa" numa caixa de texto', async () => {
    const w = montar();
    w.get(marca('pais-da-pessoa'))
      .getComponent(ChoiceSelect)
      .vm.$emit('update:modelValue', 'PT');
    await flushPromises();
    await w.get(`textarea${marca('sobre-a-pessoa')}`).setValue('Liga à tarde.');
    const pedido = await salvar(w);
    expect(pedido.contato.additional_attributes).toMatchObject({
      country_code: 'PT',
      country: 'Portugal',
      description: 'Liga à tarde.',
    });
  });
});

describe('Informações: o valor de cada tipo e quem só pode ver', () => {
  it('data, sim ou não, número e link aparecem como se leem', () => {
    const w = mount(ListaDeInformacoes, {
      props: {
        linhas: [
          {
            chave: 'conta:a',
            rotulo: 'Aniversário',
            tipo: 'date',
            valor: '1990-05-12',
          },
          { chave: 'conta:b', rotulo: 'VIP', tipo: 'checkbox', valor: false },
          { chave: 'conta:c', rotulo: 'Filhos', tipo: 'number', valor: 1500 },
          {
            chave: 'conta:d',
            rotulo: 'Site',
            tipo: 'link',
            valor: 'https://ana.com.br',
          },
          {
            chave: 'conta:e',
            rotulo: 'Ruim',
            tipo: 'link',
            valor: LINK_PERIGOSO,
          },
        ],
      },
    });
    const valor = chave => w.get(`[data-informacao="${chave}"] dd`);
    expect(valor('conta:a').text()).toBe('12/05/1990');
    expect(valor('conta:b').text()).toBe(
      'RELACIONAMENTOS_FICHA.INFORMACOES.NAO'
    );
    expect(valor('conta:c').text()).toBe('1.500');
    const link = valor('conta:d').get('a');
    expect(link.attributes()).toMatchObject({
      href: 'https://ana.com.br/',
      target: '_blank',
      rel: 'noopener noreferrer',
    });
    expect(valor('conta:e').find('a').exists()).toBe(false);
  });

  const corpo = props =>
    mount(CorpoDaFichaDaPessoa, {
      props: {
        conversas: [],
        cards: [],
        notas: [],
        arquivos: [],
        linhas: [{ chave: 'cidade', valor: 'Santos' }],
        redes: [],
        agora: Date.UTC(2026, 10, 11, 12),
        ...props,
      },
      global: { stubs },
    });

  it('quem só pode ver lê o aviso e não tem Alterar nem Escolher campos', () => {
    const w = corpo({ podeEditar: false, podeEscolherCampos: true });
    expect(w.get(marca('so-leitura')).text()).toBe(
      'RELACIONAMENTOS_FICHA.INFORMACOES.SO_LEITURA'
    );
    expect(w.find(marca('alterar')).exists()).toBe(false);
    expect(w.find(marca('escolher-campos')).exists()).toBe(false);
    expect(w.get('[data-informacao="cidade"]').text()).toContain('Santos');
  });

  const PLACA = {
    id: 1,
    chave: 'placa',
    rotulo: 'Placa do carro',
    tipo: 'text',
    valor: 'ABC1D23',
    principal: true,
  };
  const CASAMENTO = {
    id: 2,
    chave: 'casamento',
    rotulo: 'Aniversário de casamento',
    tipo: 'date',
    valor: '',
    principal: true,
  };

  it('quem pode escolher os campos da ficha tem "Escolher campos" e "Novo campo" em "Seus campos"', async () => {
    const w = corpo({
      podeEditar: true,
      podeEscolherCampos: true,
      campos: [PLACA],
    });
    expect(w.find(marca('so-leitura')).exists()).toBe(false);
    const bloco = w.get(marca('seus-campos'));
    await bloco.get(marca('escolher-campos')).trigger('click');
    expect(w.emitted('escolherCampos')).toHaveLength(1);
    await bloco.get(marca('criar-campo')).trigger('click');
    expect(w.emitted('criarCampo')).toHaveLength(1);
    expect(bloco.get(marca('criar-campo')).text()).toBe(
      'RELACIONAMENTOS_FICHA.CAMPOS.NOVO'
    );
  });

  it('"Seus campos" vem antes de Informações e mostra o vazio como "Não informado"', () => {
    const w = corpo({ campos: [PLACA, CASAMENTO] });
    const lado = w.get(marca('coluna-lado'));
    const blocos = lado
      .findAll('section')
      .map(secao => secao.attributes('data-relacionamentos'));
    expect(blocos.slice(0, 2)).toEqual(['seus-campos', 'informacoes']);
    const valor = chave =>
      w.get(`${marca('seus-campos')} [data-informacao="${chave}"] dd`).text();
    expect(valor('conta:placa')).toBe('ABC1D23');
    expect(valor('conta:casamento')).toBe(
      'RELACIONAMENTOS.COMUM.NAO_INFORMADO'
    );
    // Os campos não se repetem em Informações.
    expect(
      w.find(`${marca('informacoes')} [data-informacao="conta:placa"]`).exists()
    ).toBe(false);
  });

  it('"Seus campos" com todos vazios lista cada um, sem a frase de vazio', () => {
    const w = corpo({ campos: [CASAMENTO] });
    const bloco = w.get(marca('seus-campos'));
    expect(bloco.find('[data-vazio]').exists()).toBe(false);
    expect(bloco.get('[data-informacao="conta:casamento"]').exists()).toBe(
      true
    );
  });

  it('conta sem campos: quem pode cria o primeiro; quem não pode não vê o bloco', async () => {
    const w = corpo({ podeEditar: true, podeEscolherCampos: true });
    const bloco = w.get(marca('seus-campos'));
    expect(bloco.get('[data-vazio]').text()).toBe(
      'RELACIONAMENTOS_FICHA.CAMPOS.SEM_CAMPOS_PESSOA'
    );
    expect(bloco.find(marca('escolher-campos')).exists()).toBe(false);
    await bloco.get(marca('criar-campo')).trigger('click');
    expect(w.emitted('criarCampo')).toHaveLength(1);
    expect(corpo({}).find(marca('seus-campos')).exists()).toBe(false);
    expect(
      corpo({ podeEditar: false, podeEscolherCampos: true })
        .find(marca('seus-campos'))
        .exists()
    ).toBe(false);
  });

  it('campos que existem mas não aparecem: frase própria e "Escolher campos da ficha"', () => {
    const w = corpo({
      podeEditar: true,
      podeEscolherCampos: true,
      campos: [{ ...CASAMENTO, principal: false }],
    });
    const bloco = w.get(marca('seus-campos'));
    expect(bloco.get('[data-vazio]').text()).toBe(
      'RELACIONAMENTOS_FICHA.CAMPOS.NENHUM_NA_FICHA'
    );
    expect(bloco.find(marca('escolher-campos')).exists()).toBe(true);
  });
});
