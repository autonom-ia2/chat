import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import LinhaDeColuna from '../../components/trazer/LinhaDeColuna.vue';
// #2894 — a linha de uma coluna em "O que vou guardar": a frase de para onde
// ela vai e o "Mudar", que abre a escolha, devolve o foco e emite a troca.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const botao = (w, texto) => w.findAll('button').find(b => b.text() === texto);

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('a frase da coluna', () => {
  it('coluna extra vira frase, sem seta: “Situação” fica como informação nova', () => {
    const w = mount(LinhaDeColuna, {
      props: {
        coluna: { indice: 6, nome: 'Situação', destino: 'informacao' },
      },
    });
    expect(w.get('p').text()).toBe('“Situação” fica como informação nova.');
    expect(w.find('.i-lucide-arrow-right').exists()).toBe(false);
    expect(w.text()).not.toContain('Vira uma informação');
  });
});

describe('Trocar a coluna', () => {
  const montar = () =>
    mount(LinhaDeColuna, {
      attachTo: document.body,
      props: { coluna: { indice: 1, nome: 'Cel', destino: 'telefone' } },
    });
  const trocar = async w => {
    await botao(w, 'Mudar').trigger('click');
    await flushPromises();
  };
  const escolha = w => w.get('[role="combobox"]');

  it('abre a escolha com o foco nela', async () => {
    const w = montar();
    await trocar(w);
    expect(document.activeElement).toBe(escolha(w).element);
    expect(escolha(w).attributes('aria-expanded')).toBe('true');
    expect(botao(w, 'Mudar')).toBeUndefined();
  });

  it('fechar com Esc sem escolher volta ao Trocar, com o foco nele', async () => {
    const w = montar();
    await trocar(w);
    await escolha(w).trigger('keydown', { key: 'Escape' });
    await flushPromises();
    expect(w.find('[role="combobox"]').exists()).toBe(false);
    expect(document.activeElement).toBe(botao(w, 'Mudar').element);
    expect(w.emitted('trocar')).toBeUndefined();
  });

  it('escolher a mesma opção também volta ao Trocar', async () => {
    const w = montar();
    await trocar(w);
    await w.get('[role="option"][data-value="telefone"]').trigger('click');
    await flushPromises();
    expect(botao(w, 'Mudar')).toBeDefined();
    expect(document.activeElement).toBe(botao(w, 'Mudar').element);
    expect(w.emitted('trocar')).toBeUndefined();
  });

  it('escolher outra opção emite a troca e volta ao Trocar', async () => {
    const w = montar();
    await trocar(w);
    await w.get('[role="option"][data-value="email"]').trigger('click');
    await flushPromises();
    // A troca diz a coluna pelo lugar dela na planilha, não pelo título.
    expect(w.emitted('trocar')).toEqual([[1, 'email']]);
    expect(document.activeElement).toBe(botao(w, 'Mudar').element);
  });

  it('clicar fora fecha e volta ao Trocar sem roubar o foco de outro lugar', async () => {
    const outro = document.createElement('input');
    document.body.append(outro);
    const w = montar();
    await trocar(w);
    outro.focus();
    await flushPromises();
    expect(document.activeElement).toBe(outro);
    expect(botao(w, 'Mudar')).toBeDefined();
  });
});
