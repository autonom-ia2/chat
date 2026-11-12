import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaFerramentas from '../../components/pagina/GavetaFerramentas.vue';

// #2858 F2 — a gaveta de ferramentas com a vitrine de ferramentas prontas: o bloco "Prontas" (nome, frase, interruptor
// e "Tirar" com confirmação), "Adicionar ferramenta" levando à vitrine e, sem o cadastro manual liberado para a
// pessoa, nenhuma chamada à API das ferramentas feitas à mão (ela responderia 401). Cópia real em pt_BR.
withFullI18n('pt_BR');

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ dispatch: vi.fn(), getters: {} }),
    useMapGetter: () => computed(() => false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const manuais = vi.hoisted(() => ({
  getTools: vi.fn(),
  createTool: vi.fn(),
  updateTool: vi.fn(),
  deleteTool: vi.fn(),
  testTool: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: manuais }));
const prontasApi = vi.hoisted(() => ({
  listar: vi.fn(),
  incluir: vi.fn(),
  mudarLigada: vi.fn(),
  mudarQuando: vi.fn(),
  tirar: vi.fn(),
  experimentar: vi.fn(),
  buscaSemResultado: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/ferramentasProntas', () => ({
  default: prontasApi,
}));

const CEP = {
  id: 31,
  agente_id: 7,
  fonte: 'cep',
  ligada: true,
  usar_quando: 'Use quando o cliente informar um CEP.',
};
const DE_OUTRO_AGENTE = {
  id: 32,
  agente_id: 8,
  fonte: 'cnpj',
  ligada: true,
  usar_quando: null,
};
const ESTOQUE = {
  id: 51,
  name: 'Busca no estoque',
  description: 'Use quando perguntarem do estoque.',
  enabled: true,
  http_method: 'GET',
  endpoint_url: 'https://api.sualoja.com.br/estoque',
  request_body_template: '',
  headers_config: [],
  param_schema: [],
  response_mapping: {},
};

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
const normalizar = valor =>
  valor.replaceAll('\n', ' ').split(' ').filter(Boolean).join(' ');
const texto = () => normalizar(document.body.textContent);
const clicarNoTexto = async (rotulo, raiz = document.body) => {
  const botao = [...raiz.querySelectorAll('button')].find(
    b => b.textContent.trim() === rotulo
  );
  if (!botao) throw new Error(`botão "${rotulo}" não encontrado`);
  botao.click();
  await flushPromises();
};

// Cada gaveta montada é desmontada antes de limpar a página: limpar com ela viva deixa o Vue atualizando nós que já
// saíram do documento (o "nextSibling" de null que aparece depois do teste).
const montadas = [];

const montar = async ({
  incluidas = [CEP, DE_OUTRO_AGENTE],
  cadastroManual = false,
  manuaisDoAgente = [],
  comecarNova = false,
} = {}) => {
  prontasApi.listar.mockResolvedValue({
    data: {
      fontes: [{ chave: 'cep' }, { chave: 'cnpj' }],
      incluidas,
    },
  });
  manuais.getTools.mockResolvedValue({ data: { payload: manuaisDoAgente } });
  const wrapper = mount(GavetaFerramentas, {
    props: {
      agente: { id: 7, name: 'Bia' },
      nome: 'Bia',
      vitrine: true,
      cadastroManual,
      comecarNova,
    },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  await flushPromises();
  return wrapper;
};

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = vi.fn(function abrir() {
    this.setAttribute('open', '');
  });
  HTMLDialogElement.prototype.close = vi.fn(function fechar() {
    this.removeAttribute('open');
  });
});

beforeEach(() => {
  Object.values(manuais).forEach(fn => fn.mockReset());
  Object.values(prontasApi).forEach(fn => fn.mockReset());
  alerta.mockReset();
});

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('GavetaFerramentas · prontas sem o cadastro manual', () => {
  it('lists only the agent ready-made tools and never calls the manual tools', async () => {
    await montar();
    expect(prontasApi.listar).toHaveBeenCalled();
    expect(manuais.getTools).not.toHaveBeenCalled();
    expect(no('#ferramentas-prontas').textContent.trim()).toBe('Prontas');
    expect(todos('[data-pronta]').map(item => item.dataset.pronta)).toEqual([
      'cep',
    ]);
    expect(texto()).toContain('Endereço pelo CEP');
    expect(texto()).toContain('Use quando o cliente informar um CEP.');
    expect(no('#ferramentas-feitas')).toBeNull();
    expect(no('[data-criar-minha]')).toBeNull();
    const interruptor = no('[data-pronta="cep"] [role="switch"]');
    expect(interruptor.getAttribute('aria-checked')).toBe('true');
    expect(interruptor.getAttribute('aria-label')).toBe(
      'Usar Endereço pelo CEP no atendimento: Ligada'
    );
  });

  it('shows what the tool does when there is no "use when" sentence', async () => {
    await montar({ incluidas: [{ ...CEP, usar_quando: null }] });
    expect(texto()).toContain(
      'Acha rua, bairro, cidade e estado a partir do CEP, e o CEP a partir da rua e da cidade.'
    );
  });

  it('turns a ready-made tool off right away', async () => {
    await montar();
    prontasApi.mudarLigada.mockResolvedValue({
      data: { ...CEP, ligada: false },
    });
    no('[data-pronta="cep"] [role="switch"]').click();
    await flushPromises();
    expect(prontasApi.mudarLigada).toHaveBeenCalledWith(31, false);
    expect(
      no('[data-pronta="cep"] [role="switch"]').getAttribute('aria-checked')
    ).toBe('false');
  });

  it('a failed switch tells why in plain words', async () => {
    await montar();
    prontasApi.mudarLigada.mockRejectedValue(
      Object.assign(new Error('401'), { response: { status: 401 } })
    );
    no('[data-pronta="cep"] [role="switch"]').click();
    await flushPromises();
    expect(alerta).toHaveBeenCalledWith(
      'Você não tem permissão para cuidar das ferramentas dos agentes. Peça a quem administra a conta.'
    );
  });

  // #2881 — "Alterar quando usar" na pronta que o agente já tem.
  const escrever = async frase => {
    const campo = no('[data-pronta="cep"] textarea');
    campo.value = frase;
    campo.dispatchEvent(new Event('input'));
    await flushPromises();
  };

  it('"Alterar quando usar" opens the sentence, saves it and shows the new one', async () => {
    await montar();
    const botao = no('[data-pronta="cep"] [data-alterar-quando]');
    expect(botao.getAttribute('aria-label')).toBe(
      'Alterar quando usar Endereço pelo CEP'
    );
    botao.click();
    await flushPromises();
    expect(no('[data-pronta="cep"] textarea').value).toBe(
      'Use quando o cliente informar um CEP.'
    );
    expect(no('[data-pronta="cep"] textarea').getAttribute('maxlength')).toBe(
      '500'
    );
    prontasApi.mudarQuando.mockResolvedValue({
      data: { ...CEP, usar_quando: 'Use quando pedirem o CEP da obra.' },
    });
    await escrever('  Use quando pedirem o CEP da obra. ');
    await clicarNoTexto('Salvar', no('[data-pronta="cep"]'));
    expect(prontasApi.mudarQuando).toHaveBeenCalledWith(
      31,
      'Use quando pedirem o CEP da obra.'
    );
    expect(no('[data-pronta="cep"] textarea')).toBeNull();
    expect(no('[data-pronta="cep"] [data-frase]').textContent.trim()).toBe(
      'Use quando pedirem o CEP da obra.'
    );
    expect(alerta).toHaveBeenCalledWith(
      'Pronto. Bia já segue a frase nova de Endereço pelo CEP.'
    );
  });

  it('without a sentence of its own, the editing opens with the standard one of the tool', async () => {
    await montar({ incluidas: [{ ...CEP, usar_quando: null }] });
    no('[data-pronta="cep"] [data-alterar-quando]').click();
    await flushPromises();
    expect(no('[data-pronta="cep"] textarea').value).toContain('Use quando');
  });

  it('an empty sentence is not saved, and cancelling changes nothing', async () => {
    await montar();
    no('[data-pronta="cep"] [data-alterar-quando]').click();
    await flushPromises();
    await escrever('   ');
    await clicarNoTexto('Salvar', no('[data-pronta="cep"]'));
    expect(prontasApi.mudarQuando).not.toHaveBeenCalled();
    expect(no('[data-pronta="cep"] [role="alert"]').textContent.trim()).toBe(
      'Escreva quando o agente deve usar.'
    );
    await clicarNoTexto('Cancelar', no('[data-pronta="cep"]'));
    expect(no('[data-pronta="cep"] textarea')).toBeNull();
    expect(no('[data-pronta="cep"] [data-frase]').textContent.trim()).toBe(
      'Use quando o cliente informar um CEP.'
    );
  });

  it('a failed save keeps the editing open with what was written, and tells why', async () => {
    await montar();
    no('[data-pronta="cep"] [data-alterar-quando]').click();
    await flushPromises();
    prontasApi.mudarQuando.mockRejectedValue(
      Object.assign(new Error('401'), { response: { status: 401 } })
    );
    await escrever('Use quando pedirem o CEP da obra.');
    await clicarNoTexto('Salvar', no('[data-pronta="cep"]'));
    expect(no('[data-pronta="cep"] textarea').value).toBe(
      'Use quando pedirem o CEP da obra.'
    );
    expect(alerta).toHaveBeenCalledWith(
      'Você não tem permissão para cuidar das ferramentas dos agentes. Peça a quem administra a conta.'
    );
  });

  it('removing asks first, naming the tool, and then removes it', async () => {
    await montar();
    prontasApi.tirar.mockResolvedValue({});
    no('[data-pronta="cep"] [data-tirar]').click();
    await flushPromises();
    const dialogo = no('dialog[open]');
    expect(dialogo.textContent).toContain('Tirar Endereço pelo CEP?');
    expect(prontasApi.tirar).not.toHaveBeenCalled();
    await clicarNoTexto('Tirar', dialogo);
    expect(prontasApi.tirar).toHaveBeenCalledWith(31);
    expect(alerta).toHaveBeenCalledWith('Endereço pelo CEP saiu de Bia.');
    expect(no('[data-pronta]')).toBeNull();
  });

  it('empty: the main action is choosing a ready-made tool, which goes to the showcase', async () => {
    const wrapper = await montar({ incluidas: [] });
    expect(texto()).toContain('Bia ainda não consulta nada fora da conversa.');
    expect(no('[data-criar-minha]')).toBeNull();
    await clicarNoTexto('Escolher ferramenta pronta');
    expect(wrapper.emitted('verVitrine')).toHaveLength(1);
    expect(texto()).not.toContain('Nova ferramenta');
  });

  it('comecarNova does not open the manual form for who cannot use it', async () => {
    await montar({ comecarNova: true });
    expect(no('aside h2').textContent.trim()).toBe('Ferramentas dos agentes');
    expect(manuais.getTools).not.toHaveBeenCalled();
  });
});

describe('GavetaFerramentas · prontas com o cadastro manual', () => {
  it('shows the ready-made tools above the hand-made ones, and "Create my own"', async () => {
    await montar({ cadastroManual: true, manuaisDoAgente: [ESTOQUE] });
    expect(manuais.getTools).toHaveBeenCalledWith(7);
    expect(no('#ferramentas-prontas')).not.toBeNull();
    expect(no('#ferramentas-feitas')).not.toBeNull();
    expect(todos('[data-ferramenta]')).toHaveLength(1);
    expect(no('[data-criar-minha]')).not.toBeNull();
  });

  it('"Create my own (advanced)" opens the manual form', async () => {
    await montar({ cadastroManual: true, incluidas: [] });
    await clicarNoTexto('Criar a minha (avançado)');
    expect(no('aside h2').textContent.trim()).toBe('Nova ferramenta');
  });

  it('comecarNova opens straight in the new manual tool', async () => {
    await montar({ cadastroManual: true, comecarNova: true });
    expect(no('aside h2').textContent.trim()).toBe('Nova ferramenta');
  });
});
