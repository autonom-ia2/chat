import { nextTick } from 'vue';
import { flushPromises, mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import GavetaFerramentas from '../../components/pagina/GavetaFerramentas.vue';
import { MASCARA_DO_SEGREDO } from '../../utils/ferramentas';

// #1301 (Fase 2, protótipo ferramentas.html) — a gaveta de Ferramentas com a API atual: lista com
// interruptor, assistente de 4 passos que salva desligada, teste com valores digitados que libera
// o Ligar, edição por partes com o segredo guardado e os diálogos do módulo. Cópia real em pt_BR.
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
const api = vi.hoisted(() => ({
  getTools: vi.fn(),
  createTool: vi.fn(),
  updateTool: vi.fn(),
  deleteTool: vi.fn(),
  testTool: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: api }));

const ESTOQUE = {
  id: 31,
  name: 'Busca no estoque',
  slug: 'busca_no_estoque',
  description: 'Use quando a pessoa perguntar se uma peça tem em estoque.',
  enabled: true,
  http_method: 'GET',
  endpoint_url:
    'https://api.sualoja.com.br/estoque/busca?termo={{ termo | url_encode }}',
  request_body_template: '',
  headers_config: [
    { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
  ],
  param_schema: [
    {
      name: 'termo',
      type: 'string',
      description: 'A peça que a pessoa procura.',
      required: true,
    },
  ],
  response_mapping: {},
};
const FRETE = {
  ...ESTOQUE,
  id: 32,
  name: 'Cálculo de frete',
  description: '',
  enabled: false,
  http_method: 'POST',
  endpoint_url: 'https://api.sualoja.com.br/frete',
  headers_config: [],
  param_schema: [],
};

const no = seletor => document.querySelector(seletor);
const todos = seletor => [...document.querySelectorAll(seletor)];
// Junta o texto em espaços simples (sem regex).
const normalizar = valor =>
  valor.replaceAll('\n', ' ').split(' ').filter(Boolean).join(' ');
const texto = () => normalizar(document.body.textContent);
const rodape = () => no('aside footer');
const clicar = async seletor => {
  no(seletor).click();
  await flushPromises();
};
const clicarNoTexto = async (rotulo, raiz = document.body) => {
  const botao = [...raiz.querySelectorAll('button')].find(
    b => b.textContent.trim() === rotulo
  );
  if (!botao) throw new Error(`botão "${rotulo}" não encontrado`);
  botao.click();
  await flushPromises();
};
const digitar = async (seletor, valor) => {
  const campo = no(seletor);
  campo.value = valor;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};
const apertarEsc = async () => {
  document.dispatchEvent(
    new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
  );
  await flushPromises();
};

const montar = async (ferramentas = [ESTOQUE, FRETE]) => {
  api.getTools.mockResolvedValue({ data: { payload: ferramentas } });
  const wrapper = mount(GavetaFerramentas, {
    props: { agente: { id: 7, name: 'Bia' }, nome: 'Bia' },
    attachTo: document.body,
  });
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
  Object.values(api).forEach(fn => fn.mockReset());
  alerta.mockReset();
});

afterEach(() => {
  document.body.innerHTML = '';
});

describe('GavetaFerramentas · lista (F01)', () => {
  it('lists each tool with its sentence and the On/Off switch', async () => {
    const wrapper = await montar();
    expect(api.getTools).toHaveBeenCalledWith(7);
    expect(no('aside h2').textContent.trim()).toBe('Ferramentas');
    expect(texto()).toContain(
      'Ferramentas deixam Bia consultar outros sistemas durante a conversa'
    );
    const interruptores = todos('[data-ferramenta] [role="switch"]');
    expect(interruptores.map(i => i.getAttribute('aria-checked'))).toEqual([
      'true',
      'false',
    ]);
    expect(interruptores[0].getAttribute('aria-label')).toBe(
      'Usar Busca no estoque no atendimento: Ligada'
    );
    expect(texto()).toContain('Ligada');
    expect(texto()).toContain('Desligada');
    expect(texto()).toContain(
      'Sem "Quando usar". O agente só tem o nome para decidir.'
    );
    expect(texto()).not.toContain('busca_no_estoque');
    expect(rodape().textContent).toContain('Adicionar ferramenta');
    wrapper.unmount();
  });

  it('explains the empty state and offers to add one', async () => {
    const wrapper = await montar([]);
    expect(texto()).toContain(
      'Este agente ainda não consulta nenhum outro sistema.'
    );
    expect(no('[data-vazia] [data-adicionar]')).not.toBeNull();
    expect(rodape()).toBeNull();
    wrapper.unmount();
  });

  // #1430: sem limite de quantidade — com 11 ferramentas, "Adicionar" continua.
  it('keeps the add button with 11 tools, without any limit warning', async () => {
    const onze = Array.from({ length: 11 }, (_, i) => ({
      ...FRETE,
      id: i + 1,
    }));
    const wrapper = await montar(onze);
    expect(todos('[data-ferramenta]')).toHaveLength(11);
    expect(texto()).not.toContain('limite');
    expect(rodape().textContent).toContain('Adicionar ferramenta');
    wrapper.unmount();
  });

  it('shows the module error with a retry when the list fails', async () => {
    api.getTools.mockRejectedValueOnce({ response: { status: 500 } });
    const wrapper = mount(GavetaFerramentas, {
      props: { agente: { id: 7, name: 'Bia' }, nome: 'Bia' },
      attachTo: document.body,
    });
    await flushPromises();
    expect(no('[data-erro-lista]').textContent).toContain(
      'Não consegui carregar as ferramentas.'
    );
    api.getTools.mockResolvedValue({ data: { payload: [ESTOQUE] } });
    await clicarNoTexto('Tentar de novo');
    expect(api.getTools).toHaveBeenCalledTimes(2);
    expect(no('[data-ferramenta="31"]')).not.toBeNull();
    wrapper.unmount();
  });

  it('explains, without the list, when the API refuses (not a super admin)', async () => {
    // Pundit::NotAuthorizedError → render_unauthorized: o backend responde 401.
    api.getTools.mockRejectedValueOnce({ response: { status: 401 } });
    const wrapper = mount(GavetaFerramentas, {
      props: { agente: { id: 7, name: 'Bia' }, nome: 'Bia' },
      attachTo: document.body,
    });
    await flushPromises();
    expect(no('[data-sem-permissao]').textContent).toContain(
      'Ferramentas são configuradas só pela equipe da plataforma'
    );
    expect(texto()).not.toContain('Sua permissão mudou');
    await clicarNoTexto('Voltar ao agente');
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('asks before turning a tool off, then PATCHes only enabled', async () => {
    api.updateTool.mockResolvedValue({ data: { ...ESTOQUE, enabled: false } });
    const wrapper = await montar();
    await clicar('[data-ferramenta="31"] [role="switch"]');
    expect(api.updateTool).not.toHaveBeenCalled();
    const dialogo = no('dialog[open]');
    expect(dialogo.textContent).toContain('Desligar Busca no estoque?');
    expect(dialogo.textContent).toContain(
      'Bia para de usar esta ferramenta nas conversas a partir de agora.'
    );
    await clicarNoTexto('Desligar', dialogo);
    expect(api.updateTool).toHaveBeenCalledWith(7, 31, { enabled: false });
    expect(alerta).toHaveBeenCalledWith('Busca no estoque desligada.');
    expect(
      no('[data-ferramenta="31"] [role="switch"]').getAttribute('aria-checked')
    ).toBe('false');
    wrapper.unmount();
  });

  it('never turns a tool on straight from the list: it goes to the test first', async () => {
    const wrapper = await montar();
    await clicar('[data-ferramenta="32"] [role="switch"]');
    expect(api.updateTool).not.toHaveBeenCalled();
    expect(no('aside h2').textContent.trim()).toBe('Testar Cálculo de frete');
    expect(no('[data-precisa-testar]').textContent).toContain(
      'Antes de ligar, faça uma chamada de teste.'
    );
    wrapper.unmount();
  });
});

describe('GavetaFerramentas · nova ferramenta (F03–F06)', () => {
  it('walks the 4 steps from the generic example and saves it turned off', async () => {
    api.createTool.mockResolvedValue({
      data: { ...ESTOQUE, id: 40, enabled: false },
    });
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    expect(no('aside h2').textContent.trim()).toBe('Nova ferramenta');
    expect(texto()).toContain('Passo 1 de 4');

    await clicarNoTexto('Continuar', rodape());
    expect(no('[data-erro-campo]').textContent.trim()).toBe('Escreva um nome.');
    expect(document.activeElement).toBe(no('[data-campo-nome]'));

    await clicar('[data-usar-exemplo]');
    expect(no('[data-exemplo-aplicado]')).not.toBeNull();
    await clicarNoTexto('Continuar', rodape());
    expect(texto()).toContain('Passo 2 de 4');
    expect(no('[data-campo-endereco]').value).toBe(
      'https://api.sualoja.com.br/estoque/busca?termo={{ termo | url_encode }}'
    );
    expect(texto()).not.toContain('gira');
    await clicarNoTexto('Continuar', rodape());
    expect(texto()).toContain('Passo 3 de 4');
    expect(no('[data-sem-corpo]')).not.toBeNull();
    await clicarNoTexto('Continuar', rodape());
    expect(texto()).toContain('Passo 4 de 4');
    expect(no('[data-salva-desligada]')).not.toBeNull();

    await clicarNoTexto('Salvar e testar', rodape());
    expect(
      no('[data-cabecalho="0"] [data-erro-campo]').textContent.trim()
    ).toBe('Digite o valor.');
    expect(api.createTool).not.toHaveBeenCalled();
    expect(no('[data-campo-valor]').type).toBe('password');
    await digitar('[data-campo-valor]', 'sk_teste');
    await clicarNoTexto('Salvar e testar', rodape());

    expect(api.createTool).toHaveBeenCalledWith(
      7,
      expect.objectContaining({
        name: 'Busca no estoque',
        enabled: false,
        http_method: 'GET',
        headers_config: [{ key: 'x-api-key', value: 'sk_teste', secret: true }],
        param_schema: [
          expect.objectContaining({ name: 'termo', required: true }),
        ],
      })
    );
    expect(no('aside h2').textContent.trim()).toBe('Testar Busca no estoque');
    wrapper.unmount();
  });

  it('separates the "Exemplo:" label from the example text with one space', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    const exemplos = todos('[data-exemplo]').map(p => p.textContent.trim());
    expect(exemplos.length).toBeGreaterThan(0);
    exemplos.forEach(linha => {
      expect(linha.startsWith('Exemplo: ')).toBe(true);
      expect(linha.startsWith('Exemplo:  ')).toBe(false);
    });
    wrapper.unmount();
  });

  it('warns once when "Quando usar" is empty and goes on at the second try', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await digitar('[data-campo-nome]', 'Estoque');
    await clicarNoTexto('Continuar', rodape());
    expect(no('[data-aviso-quando]').textContent).toContain(
      'Sem isto, o agente só tem o nome para decidir.'
    );
    await clicarNoTexto('Continuar', rodape());
    expect(texto()).toContain('Passo 2 de 4');
    wrapper.unmount();
  });

  // #1425: o backend codifica cada valor do endereço; não há mais aviso de url_encode.
  it('checks the address, with no url_encode warning for a query variable', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await digitar('[data-campo-nome]', 'Estoque');
    await digitar('[data-campo-quando]', 'Use para estoque.');
    await clicarNoTexto('Continuar', rodape());
    await digitar('[data-campo-endereco]', 'http://192.168.0.1/x');
    await clicarNoTexto('Continuar', rodape());
    expect(no('[data-erro-campo]').textContent.trim()).toBe(
      'Use um endereço que comece com https://.'
    );
    await digitar(
      '[data-campo-endereco]',
      'https://api.loja.com.br/b?t={{termo}}'
    );
    expect(no('[data-aviso-codificar]')).toBeNull();
    expect(no('[data-aviso-criar]').textContent).toContain(
      'Você vai criar {{termo}} no próximo passo.'
    );
    wrapper.unmount();
  });

  it('asks "Sair sem salvar?" instead of closing with something typed', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await digitar('[data-campo-nome]', 'Estoque');
    await apertarEsc();
    expect(wrapper.emitted('fechar')).toBeUndefined();
    const dialogo = no('dialog[open]');
    expect(dialogo.textContent).toContain('Sair sem salvar?');
    await clicarNoTexto('Sair sem salvar', dialogo);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('shows the API message and the likely step when saving fails', async () => {
    api.createTool.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'Endpoint url deve usar HTTPS' },
      },
    });
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await clicar('[data-usar-exemplo]');
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await digitar('[data-campo-valor]', 'sk');
    await clicarNoTexto('Salvar e testar', rodape());
    const erro = no('[data-erro-salvar]');
    expect(erro.textContent).toContain('Não consegui salvar. Nada foi salvo.');
    expect(erro.textContent).toContain(
      'O sistema disse: “Endpoint url deve usar HTTPS”.'
    );
    expect(
      todos('[data-ir-para-passo]').map(b => b.textContent.trim())
    ).toEqual(['Ir para o passo 2, para onde chama']);
    wrapper.unmount();
  });
});

describe('GavetaFerramentas · teste (F07)', () => {
  const abrirTeste = async () => {
    const wrapper = await montar();
    await clicar('[data-ferramenta="31"] [data-abrir]');
    await clicarNoTexto('Testar', rodape());
    return wrapper;
  };

  it('asks for the values, warns it is a real call and previews what the backend builds', async () => {
    const wrapper = await abrirTeste();
    expect(no('[data-chamada-real]').textContent).toContain(
      'Esta é uma chamada de verdade, com as chaves salvas.'
    );
    await clicarNoTexto('Fazer chamada de teste', rodape());
    expect(api.testTool).not.toHaveBeenCalled();
    expect(no('[data-erro-campo]').textContent.trim()).toBe(
      'Preencha para testar.'
    );
    await digitar('[data-valor-teste]', 'pastilha de freio');
    expect(no('[data-previa]').textContent).toContain(
      'GET https://api.sualoja.com.br/estoque/busca?termo=pastilha+de+freio'
    );
    expect(no('[data-previa]').textContent).toContain('x-api-key: ••••••');
    wrapper.unmount();
  });

  it('shows what the agent gets when it works', async () => {
    api.testTool.mockResolvedValue({
      data: { status: 'ok', body: '{"itens":[{"nome":"Pastilha"}]}' },
    });
    const wrapper = await abrirTeste();
    await digitar('[data-valor-teste]', 'pastilha de freio');
    await clicarNoTexto('Fazer chamada de teste', rodape());
    expect(api.testTool).toHaveBeenCalledWith(7, 31, {
      termo: 'pastilha de freio',
    });
    expect(no('[data-deu-certo]').textContent).toContain(
      'Deu certo. O sistema respondeu.'
    );
    expect(no('[data-deu-certo]').textContent).toContain(
      'O que o agente recebe'
    );
    expect(no('[data-resposta-json]').textContent).toContain(
      '"nome": "Pastilha"'
    );
    expect(rodape().textContent).toContain('Voltar para a ferramenta');
    wrapper.unmount();
  });

  it('turns the tool on only after a test that worked (PATCH enabled:true)', async () => {
    api.testTool.mockResolvedValue({ data: { status: 'ok', body: 'ok' } });
    api.updateTool.mockResolvedValue({ data: { ...FRETE, enabled: true } });
    const wrapper = await montar();
    await clicar('[data-ferramenta="32"] [role="switch"]');
    expect(rodape().textContent).not.toContain('Ligar ferramenta');
    await clicarNoTexto('Fazer chamada de teste', rodape());
    expect(api.testTool).toHaveBeenCalledWith(7, 32, {});
    await clicarNoTexto('Ligar ferramenta', rodape());
    expect(api.updateTool).toHaveBeenCalledWith(7, 32, { enabled: true });
    expect(alerta).toHaveBeenCalledWith(
      'Ligada. Bia já pode usar no atendimento.'
    );
    expect(
      no('[data-ferramenta="32"] [role="switch"]').getAttribute('aria-checked')
    ).toBe('true');
    wrapper.unmount();
  });

  it('translates the failure, keeps the original detail and points where to fix', async () => {
    api.testTool.mockRejectedValue({
      response: {
        status: 422,
        data: { error: 'tool_http_error: 401 Unauthorized' },
      },
    });
    const wrapper = await abrirTeste();
    await digitar('[data-valor-teste]', 'pastilha');
    await clicarNoTexto('Fazer chamada de teste', rodape());
    const falha = no('[data-falha]');
    expect(falha.textContent).toContain('O sistema recusou a chave de acesso.');
    expect(falha.textContent).toContain(
      'A ferramenta continua ligada, como estava. Corrija em Como entra no sistema.'
    );
    expect(falha.textContent).toContain('tool_http_error: 401 Unauthorized');
    expect(rodape().textContent).not.toContain('Ligar ferramenta');
    await clicarNoTexto('Corrigir a chave', rodape());
    expect(no('aside h2').textContent.trim()).toBe('Alterar Busca no estoque');
    expect(no('[data-guardado]').textContent).toContain('Guardado');
    wrapper.unmount();
  });
});

describe('GavetaFerramentas · ver e alterar (F09, F10, F11)', () => {
  const abrirDetalhe = async () => {
    const wrapper = await montar();
    await clicar('[data-ferramenta="31"] [data-abrir]');
    return wrapper;
  };

  it('describes the tool in sentences, with Alterar for each part', async () => {
    const wrapper = await abrirDetalhe();
    expect(no('aside h2').textContent.trim()).toBe('Busca no estoque');
    const detalhe = normalizar(no('[data-detalhe]').textContent);
    expect(detalhe).toContain('Bia usa nas conversas.');
    expect(detalhe).toContain('Busca em api.sualoja.com.br');
    expect(detalhe).toContain('1 informação: termo (texto).');
    expect(detalhe).toContain('Com 1 chave secreta (x-api-key).');
    expect(
      todos('[data-alterar]').map(b => b.getAttribute('aria-label'))
    ).toEqual([
      'Alterar o que faz',
      'Alterar para onde chama',
      'Alterar o que o agente preenche',
      'Alterar como entra',
    ]);
    wrapper.unmount();
  });

  it('keeps an untouched stored secret by sending the mask with the same key', async () => {
    api.updateTool.mockResolvedValue({ data: ESTOQUE });
    const wrapper = await abrirDetalhe();
    await clicar('[data-linha="4"] [data-alterar]');
    expect(no('[data-aviso-ligada]').textContent).toContain(
      'Esta ferramenta está ligada.'
    );
    await clicar('[data-salvar-ligada]');
    expect(api.updateTool).toHaveBeenCalledWith(
      7,
      31,
      expect.objectContaining({
        headers_config: [
          { key: 'x-api-key', value: MASCARA_DO_SEGREDO, secret: true },
        ],
      })
    );
    expect(api.updateTool.mock.calls[0][2]).not.toHaveProperty('enabled');
    expect(no('[data-salvo]').textContent).toContain(
      'Salvo. Já vale nas conversas.'
    );
    wrapper.unmount();
  });

  it('asks to retype a renamed secret and never sends the mask under the new key', async () => {
    api.updateTool.mockResolvedValue({ data: { ...ESTOQUE, enabled: false } });
    const wrapper = await abrirDetalhe();
    await clicar('[data-linha="4"] [data-alterar]');
    expect(texto()).toContain(
      'Se mudar este nome, você vai precisar digitar o valor de novo.'
    );
    await digitar('[data-campo-chave]', 'x-api-token');
    expect(no('[data-redigitar]').textContent).toContain(
      'Você mudou o nome do cabeçalho. Digite o valor de novo'
    );
    await clicarNoTexto('Desligar, salvar e testar', rodape());
    expect(api.updateTool).not.toHaveBeenCalled();
    expect(no('[data-erro-campo]').textContent.trim()).toBe(
      'Digite o valor de novo para salvar.'
    );
    await digitar('[data-campo-valor]', 'novo-segredo');
    await clicarNoTexto('Desligar, salvar e testar', rodape());
    const enviado = api.updateTool.mock.calls[0][2];
    expect(enviado.enabled).toBe(false);
    expect(enviado.headers_config).toEqual([
      { key: 'x-api-token', value: 'novo-segredo', secret: true },
    ]);
    expect(JSON.stringify(enviado)).not.toContain(MASCARA_DO_SEGREDO);
    expect(no('aside h2').textContent.trim()).toBe('Testar Busca no estoque');
    expect(no('[data-precisa-testar]')).not.toBeNull();
    wrapper.unmount();
  });

  it('treats turning off "É segredo" of a stored value like a rename', async () => {
    const wrapper = await abrirDetalhe();
    await clicar('[data-linha="4"] [data-alterar]');
    await clicar('[data-segredo]');
    expect(no('[data-redigitar]').textContent).toContain(
      'Você desligou "É segredo". Digite o valor de novo'
    );
    expect(no('[data-campo-valor]').value).toBe('');
    wrapper.unmount();
  });

  it('deletes with the module dialog, never window.confirm', async () => {
    const confirmar = vi.spyOn(window, 'confirm');
    api.deleteTool.mockResolvedValue({});
    const wrapper = await abrirDetalhe();
    await clicar('[data-excluir]');
    const dialogo = no('dialog[open]');
    expect(dialogo.textContent).toContain('Excluir Busca no estoque?');
    expect(dialogo.textContent).toContain(
      'Se for só uma pausa, desligue em vez de excluir.'
    );
    await clicarNoTexto('Excluir', dialogo);
    expect(api.deleteTool).toHaveBeenCalledWith(7, 31);
    expect(alerta).toHaveBeenCalledWith('Busca no estoque foi excluída.');
    expect(no('[data-ferramenta="31"]')).toBeNull();
    expect(confirmar).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows the error inside the dialog and keeps the tool when deleting fails', async () => {
    api.deleteTool.mockRejectedValue({ response: { status: 500 } });
    const wrapper = await abrirDetalhe();
    await clicar('[data-excluir]');
    const dialogo = no('dialog[open]');
    await clicarNoTexto('Excluir', dialogo);
    expect(dialogo.textContent).toContain('Não consegui excluir.');
    expect(dialogo.textContent).toContain('Nada mudou.');
    expect(no('[data-detalhe]')).not.toBeNull();
    wrapper.unmount();
  });

  it('explains when the permission changes in the middle (401)', async () => {
    api.updateTool.mockRejectedValue({ response: { status: 401 } });
    const wrapper = await abrirDetalhe();
    await clicar('[data-linha="1"] [data-alterar]');
    await clicar('[data-salvar-ligada]');
    expect(no('[data-sem-permissao]').textContent).toContain(
      'Sua permissão mudou. Nada foi salvo.'
    );
    wrapper.unmount();
  });
});

describe('GavetaFerramentas · revisão independente', () => {
  it('saves back the hidden Content-Type and the whole response_mapping', async () => {
    const comExtras = {
      ...FRETE,
      headers_config: [
        { key: 'Content-Type', value: 'application/xml', secret: false },
      ],
      response_mapping: { template: '{{ response.total }}', outro: 'x' },
    };
    api.updateTool.mockResolvedValue({ data: comExtras });
    const wrapper = await montar([comExtras]);
    await clicar('[data-ferramenta="32"] [data-abrir]');
    await clicar('[data-linha="1"] [data-alterar]');
    await digitar('[data-campo-quando]', 'Use para frete.');
    await clicarNoTexto('Salvar', rodape());
    const enviado = api.updateTool.mock.calls[0][2];
    expect(enviado.headers_config).toEqual([
      { key: 'Content-Type', value: 'application/xml', secret: false },
    ]);
    expect(enviado.response_mapping).toEqual({
      template: '{{ response.total }}',
      outro: 'x',
    });
    expect(enviado.description).toBe('Use para frete.');
    wrapper.unmount();
  });

  it('asks before dropping a stored secret whose name was erased', async () => {
    api.updateTool.mockResolvedValue({ data: { ...ESTOQUE, enabled: false } });
    const wrapper = await montar();
    await clicar('[data-ferramenta="31"] [data-abrir]');
    await clicar('[data-linha="4"] [data-alterar]');
    await digitar('[data-campo-chave]', '');
    await clicarNoTexto('Desligar, salvar e testar', rodape());
    expect(api.updateTool).not.toHaveBeenCalled();
    const dialogo = no('dialog[open]');
    expect(dialogo.textContent).toContain('Remover este cabeçalho?');
    await clicarNoTexto('Remover', dialogo);
    expect(api.updateTool).toHaveBeenCalledTimes(1);
    expect(api.updateTool.mock.calls[0][2].headers_config).toEqual([]);
    wrapper.unmount();
  });

  it('keeps password managers away from secret values', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await clicar('[data-usar-exemplo]');
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    const campo = no('[data-campo-valor]');
    expect(campo.type).toBe('password');
    expect(campo.getAttribute('autocomplete')).toBe('new-password');
    expect(campo.hasAttribute('data-1p-ignore')).toBe(true);
    expect(campo.getAttribute('data-lpignore')).toBe('true');
    wrapper.unmount();
  });

  it('keeps Mostrar with its own card when another one is removed', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await clicar('[data-usar-exemplo]');
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await clicar('[data-adicionar-cabecalho]');
    await clicar('[data-cabecalho="1"] [data-mostrar]');
    expect(no('[data-cabecalho="1"] [data-campo-valor]').type).toBe('text');
    await clicar('[data-cabecalho="0"] [data-remover]');
    expect(todos('[data-cabecalho]')).toHaveLength(1);
    expect(no('[data-cabecalho="0"] [data-campo-valor]').type).toBe('text');
    wrapper.unmount();
  });

  it('asks before leaving an edit with changes through Voltar', async () => {
    const wrapper = await montar();
    await clicar('[data-ferramenta="31"] [data-abrir]');
    await clicar('[data-linha="1"] [data-alterar]');
    await digitar('[data-campo-quando]', 'Outra frase.');
    await clicarNoTexto('Voltar', rodape());
    const dialogo = no('dialog[open]');
    expect(dialogo.textContent).toContain('Sair sem salvar?');
    await clicarNoTexto('Sair sem salvar', dialogo);
    expect(no('[data-detalhe]')).not.toBeNull();
    wrapper.unmount();
  });

  it('counts any field of the 4 steps as a change (here, only POST)', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await digitar('[data-campo-nome]', 'X');
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await clicar('[role="radio"][aria-checked="false"]');
    await clicarNoTexto('Voltar', rodape());
    await digitar('[data-campo-nome]', '');
    await clicarNoTexto('Cancelar', rodape());
    expect(no('dialog[open]').textContent).toContain('Sair sem salvar?');
    wrapper.unmount();
  });

  it('sends a decimal with a point and leaves no Detalhe when the network fails', async () => {
    const comNumero = {
      ...FRETE,
      param_schema: [
        { name: 'peso', type: 'number', description: '', required: true },
      ],
    };
    api.testTool.mockRejectedValue(new Error('Network Error'));
    const wrapper = await montar([comNumero]);
    await clicar('[data-ferramenta="32"] [role="switch"]');
    await digitar('[data-valor-teste]', '12,5');
    await clicarNoTexto('Fazer chamada de teste', rodape());
    expect(api.testTool).toHaveBeenCalledWith(7, 32, { peso: '12.5' });
    const falha = no('[data-falha]');
    expect(falha.textContent).toContain('Não consegui fazer a chamada.');
    expect(falha.textContent).not.toContain('Detalhe');
    expect(falha.textContent).not.toContain('REDE');
    wrapper.unmount();
  });

  it('focuses the first yes/no option and ties the error to the group', async () => {
    const comSimNao = {
      ...FRETE,
      param_schema: [
        { name: 'urgente', type: 'boolean', description: '', required: true },
      ],
    };
    const wrapper = await montar([comSimNao]);
    await clicar('[data-ferramenta="32"] [role="switch"]');
    await clicarNoTexto('Fazer chamada de teste', rodape());
    await nextTick();
    const grupo = no('[role="radiogroup"]');
    expect(document.activeElement).toBe(grupo.querySelector('[role="radio"]'));
    const erroId = grupo.getAttribute('aria-describedby');
    expect(document.getElementById(erroId).textContent.trim()).toBe(
      'Preencha para testar.'
    );
    wrapper.unmount();
  });

  it('warns when a header name has characters the system refuses', async () => {
    const wrapper = await montar();
    await clicar('#ferramentas-adicionar');
    await clicar('[data-usar-exemplo]');
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await clicarNoTexto('Continuar', rodape());
    await digitar('[data-campo-chave]', 'x api_key');
    await digitar('[data-campo-valor]', 'v');
    await clicarNoTexto('Salvar e testar', rodape());
    expect(api.createTool).not.toHaveBeenCalled();
    expect(
      no('[data-cabecalho="0"] [data-erro-campo]').textContent.trim()
    ).toBe('Use só letras sem acento, números e hífen. Ex.: x-api-key');
    expect(document.activeElement).toBe(no('[data-campo-chave]'));
    wrapper.unmount();
  });
});
