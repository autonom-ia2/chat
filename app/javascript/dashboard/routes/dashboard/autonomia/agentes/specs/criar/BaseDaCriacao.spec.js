import { mount, flushPromises } from '@vue/test-utils';
import BaseDaCriacao from '../../components/criar/BaseDaCriacao.vue';

// #1503 — a caixa "Base de conhecimento de {nome}" da etapa Conte. Os estados vêm da conversa
// (estadoDoMaterial); a caixa só os mostra e emite o que a pessoa fez.
const ESTADOS = {
  1: 'pronto',
  2: 'lendo',
  3: 'atencao',
  4: 'fila',
  5: 'grande',
  6: 'enviando',
};
const material = (id, extra = {}) => ({
  id,
  nome: `arquivo-${id}.pdf`,
  tipo: 'arquivo',
  ...extra,
});
const VARIOS = [
  material(1, { nome: 'Cardápio.pdf' }),
  material(2, { nome: 'www.loja.com.br', tipo: 'site' }),
  material(3, { nome: 'Tabela.xlsx' }),
  material(4, { nome: 'Regras.docx' }),
  material(5, { nome: 'Catálogo.pdf' }),
  material(6, { nome: 'Horários.pdf' }),
];

const montar = props =>
  mount(BaseDaCriacao, {
    attachTo: document.body,
    props: {
      nome: 'Duda',
      itens: [],
      estadoDoMaterial: item => ESTADOS[item.id] || 'lendo',
      podeGerenciar: true,
      ...props,
    },
  });

const escolherArquivo = async (wrapper, arquivo) => {
  const seletor = wrapper.get('[data-base-seletor]');
  Object.defineProperty(seletor.element, 'files', {
    value: [arquivo],
    configurable: true,
  });
  await seletor.trigger('change');
};
const arquivoDe = (nome, tamanho = 1000) => {
  const arquivo = new File(['x'], nome, { type: 'application/pdf' });
  Object.defineProperty(arquivo, 'size', { value: tamanho });
  return arquivo;
};
const linha = (wrapper, id) => wrapper.get(`[data-material-id="${id}"]`);
const abrirTirar = async (wrapper, id) => {
  await linha(wrapper, id).get('[aria-haspopup]').trigger('click');
  await flushPromises();
  const tirar = [...document.querySelectorAll('[role="menuitem"]')].find(item =>
    item.textContent.includes('AGENTS.JORNADA.PAGINA.SABE.TIRAR')
  );
  tirar.click();
  await flushPromises();
};

describe('BaseDaCriacao', () => {
  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('shows the title with the agent name and, empty, one sentence and one button', () => {
    const wrapper = montar();
    expect(wrapper.get('h2').text()).toBe('AGENTS.JORNADA.CRIAR.BASE.TITULO');
    expect(wrapper.get('[data-base-vazia]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.BASE.VAZIO'
    );
    expect(wrapper.find('[data-base-lista]').exists()).toBe(false);
    const botoes = wrapper.findAll('button');
    expect(botoes).toHaveLength(1);
    expect(botoes[0].text()).toBe('AGENTS.JORNADA.CRIAR.BASE.ADICIONAR');
    expect(botoes[0].classes()).toContain('min-h-11');
  });

  it('shows each item with its state in words: reading, ready or with a problem', () => {
    const wrapper = montar({ itens: VARIOS });
    const estados = wrapper
      .findAll('[data-fonte]')
      .map(item => item.attributes('data-estado'));
    // enviando e na fila também são "lendo" para quem olha a caixa.
    expect(estados).toEqual([
      'pronto',
      'lendo',
      'falha',
      'lendo',
      'falha',
      'lendo',
    ]);
    expect(linha(wrapper, 1).text()).toContain(
      'AGENTS.JORNADA.PAGINA.SABE.PRONTO'
    );
    expect(linha(wrapper, 2).text()).toContain(
      'AGENTS.JORNADA.PAGINA.SABE.LENDO'
    );
    expect(linha(wrapper, 3).text()).toContain(
      'AGENTS.JORNADA.PAGINA.SABE.FALHA_ARQUIVO'
    );
    // Grande demais: o texto diz o que fazer, não "não consegui ler".
    expect(linha(wrapper, 5).text()).toContain(
      'AGENTS.JORNADA.CRIAR.BASE.GRANDE_TEXTO'
    );
    expect(wrapper.find('[data-base-vazia]').exists()).toBe(false);
  });

  it('shows one icon per kind: a globe for a website, a page for a file', () => {
    const wrapper = montar({ itens: VARIOS.slice(0, 2) });
    expect(linha(wrapper, 1).find('.i-lucide-file-text').exists()).toBe(true);
    expect(linha(wrapper, 2).find('.i-lucide-globe').exists()).toBe(true);
    expect(linha(wrapper, 2).text()).toContain('www.loja.com.br');
  });

  it('never offers "read again" while creating (only remove)', async () => {
    const wrapper = montar({ itens: VARIOS.slice(1, 2) });
    await linha(wrapper, 2).get('[aria-haspopup]').trigger('click');
    await flushPromises();
    const itens = [...document.querySelectorAll('[role="menuitem"]')].map(
      item => item.textContent.trim()
    );
    expect(itens).toEqual(['AGENTS.JORNADA.PAGINA.SABE.TIRAR']);
  });

  it('adds a file through the box', async () => {
    const wrapper = montar();
    await wrapper.get('[data-base-adicionar-botao]').trigger('click');
    expect(
      wrapper.get('[data-base-adicionar-botao]').attributes('aria-expanded')
    ).toBe('true');
    expect(document.activeElement).toBe(
      wrapper.get('[data-base-arquivo]').element
    );
    const arquivo = arquivoDe('Cardápio.pdf');
    await escolherArquivo(wrapper, arquivo);
    expect(wrapper.emitted('anexar')).toEqual([[arquivo]]);
    expect(wrapper.find('[data-base-adicionar]').exists()).toBe(false);
    expect(wrapper.get('[data-base-anuncio]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.BASE.ENTROU'
    );
  });

  it('refuses a file over 25 MB and the 31st item before sending', async () => {
    const grande = montar();
    await escolherArquivo(grande, arquivoDe('Grande.pdf', 26 * 1024 * 1024));
    expect(grande.emitted('anexar')).toBeUndefined();
    expect(grande.get('[data-base-aviso]').text()).toContain(
      'AGENTS.JORNADA.PAGINA.SABE.GRANDE'
    );

    const cheia = montar({
      itens: Array.from({ length: 30 }, (_, i) => material(100 + i)),
    });
    await escolherArquivo(cheia, arquivoDe('Mais um.pdf'));
    expect(cheia.emitted('anexar')).toBeUndefined();
    expect(cheia.get('[data-base-aviso]').text()).toContain(
      'AGENTS.JORNADA.PAGINA.SABE.LIMITE'
    );
  });

  it('adds a website, checking the address without sending a wrong one', async () => {
    const wrapper = montar();
    await wrapper.get('[data-base-adicionar-botao]').trigger('click');
    const campo = wrapper.get('[data-base-site]');
    await campo.setValue('minha loja');
    await wrapper.get('[data-base-adicionar] form').trigger('submit');
    expect(wrapper.emitted('site')).toBeUndefined();
    expect(wrapper.get('[data-base-erro-site]').text()).toBe(
      'AGENTS.JORNADA.PAGINA.SABE.SITE_ERRO'
    );
    expect(campo.attributes('aria-invalid')).toBe('true');

    await campo.setValue('www.loja.com.br');
    await wrapper.get('[data-base-adicionar] form').trigger('submit');
    expect(wrapper.emitted('site')).toEqual([['https://www.loja.com.br/']]);
    expect(wrapper.find('[data-base-adicionar]').exists()).toBe(false);
  });

  it('asks inside the row before removing, and removes only on "Remove"', async () => {
    const confirmar = vi.spyOn(window, 'confirm');
    const wrapper = montar({ itens: VARIOS.slice(0, 2) });
    await abrirTirar(wrapper, 1);

    const caixa = linha(wrapper, 1).get('[data-confirmar-tirar]');
    expect(caixa.attributes('role')).toBe('group');
    expect(caixa.text()).toContain('AGENTS.JORNADA.CRIAR.BASE.TIRAR_TITULO');
    expect(caixa.text()).toContain('AGENTS.JORNADA.CRIAR.BASE.TIRAR_TEXTO');
    expect(document.activeElement).toBe(
      caixa.get('[data-cancelar-tirar]').element
    );
    expect(wrapper.emitted('tirar')).toBeUndefined();
    expect(confirmar).not.toHaveBeenCalled();

    await caixa.get('[data-sim-tirar]').trigger('click');
    await flushPromises();
    expect(wrapper.emitted('tirar')).toEqual([[VARIOS[0]]]);
    expect(wrapper.find('[data-confirmar-tirar]').exists()).toBe(false);
    expect(document.activeElement).toBe(
      wrapper.get('[data-base-adicionar-botao]').element
    );
    expect(wrapper.get('[data-base-anuncio]').text()).toBe(
      'AGENTS.JORNADA.CRIAR.BASE.TIROU'
    );
    confirmar.mockRestore();
  });

  it('cancels the removal with the button or Esc, and gives focus back to the row', async () => {
    const wrapper = montar({ itens: VARIOS.slice(0, 2) });
    await abrirTirar(wrapper, 2);
    await linha(wrapper, 2).get('[data-cancelar-tirar]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-confirmar-tirar]').exists()).toBe(false);
    expect(document.activeElement).toBe(
      linha(wrapper, 2).get('[aria-haspopup]').element
    );

    await abrirTirar(wrapper, 2);
    await linha(wrapper, 2)
      .get('[data-confirmar-tirar]')
      .trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(wrapper.find('[data-confirmar-tirar]').exists()).toBe(false);
    expect(wrapper.emitted('tirar')).toBeUndefined();
  });

  it('"send another" opens the file picker for a file and the address field for a site', async () => {
    const wrapper = montar({
      itens: [material(3), material(7, { nome: 'loja.com', tipo: 'site' })],
      estadoDoMaterial: () => 'atencao',
    });
    const clique = vi.spyOn(
      wrapper.get('[data-base-seletor]').element,
      'click'
    );
    await linha(wrapper, 3).get('[data-mandar-outro]').trigger('click');
    expect(clique).toHaveBeenCalledTimes(1);

    await linha(wrapper, 7).get('[data-mandar-outro]').trigger('click');
    await flushPromises();
    expect(document.activeElement).toBe(
      wrapper.get('[data-base-site]').element
    );
  });

  it('a view-only seat sees the base without any writing action', () => {
    const wrapper = montar({ itens: VARIOS, podeGerenciar: false });
    expect(wrapper.findAll('[data-fonte]')).toHaveLength(6);
    expect(wrapper.find('[data-base-adicionar-botao]').exists()).toBe(false);
    expect(wrapper.find('[data-base-seletor]').exists()).toBe(false);
    expect(wrapper.find('[aria-haspopup]').exists()).toBe(false);
    expect(wrapper.find('[data-mandar-outro]').exists()).toBe(false);
  });

  it('shows the reading error with one way out', async () => {
    const wrapper = montar({ erroAoLer: true });
    const erro = wrapper.get('[data-base-erro]');
    expect(erro.text()).toContain('AGENTS.JORNADA.CRIAR.BASE.ERRO_LER');
    expect(erro.text()).toContain(
      'AGENTS.JORNADA.CRIAR.BASE.ERRO_LER_GARANTIA'
    );
    expect(wrapper.find('[data-base-vazia]').exists()).toBe(false);
    await erro.get('button').trigger('click');
    expect(wrapper.emitted('reler')).toHaveLength(1);
  });

  it('inside the phone drawer it drops its own frame and title (the drawer has them)', () => {
    const wrapper = montar({ naGaveta: true });
    expect(wrapper.find('h2').exists()).toBe(false);
    expect(wrapper.get('[data-base]').attributes('aria-label')).toBe(
      'AGENTS.JORNADA.CRIAR.BASE.TITULO'
    );
    expect(wrapper.get('[data-base]').classes()).not.toContain('ring-1');
  });

  it('never renders a native select', () => {
    const wrapper = montar({ itens: VARIOS });
    expect(wrapper.find('select').exists()).toBe(false);
  });
});
