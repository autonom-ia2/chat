import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDeExemplo } from '../../demo/trazer';
import OQueVouGuardar from '../../components/trazer/OQueVouGuardar.vue';
// #2894 — o bloco "O que vou guardar" do Conferir: nasce fechado, o título é
// um botão do tamanho dos outros títulos e os botões das colunas são os da casa.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

const leitura = leituraDeExemplo('l1');

// O jsdom não tem scrollIntoView, que o ChoiceSelect chama ao abrir a lista.
beforeEach(() => {
  Element.prototype.scrollIntoView = vi.fn();
});
afterEach(() => {
  document.body.innerHTML = '';
});

describe('O que vou guardar', () => {
  const montar = () =>
    mount(OQueVouGuardar, { props: { colunas: leitura.colunas } });

  it('nasce fechado', () => {
    const w = montar();
    expect(w.get('h2 button').attributes('aria-expanded')).toBe('false');
    expect(w.get('ul').attributes('style')).toContain('display: none');
  });

  // #2896 — a coluna que é informação nova ganhou o "Salvar", também botão da
  // casa e discreto como os outros dois. Os três têm 44 px de altura mínima
  // (alvo de toque).
  it('Mudar, Não guardar e Salvar são botões da casa, com 44 px de altura e rótulo claro', () => {
    const w = montar();
    const linha = w.get('[data-coluna="Aniversário"]');
    const botoes = linha.findAll('button');
    expect(botoes.map(b => b.text())).toEqual([
      'Mudar',
      'Não guardar',
      'Salvar',
    ]);
    botoes.forEach(b => {
      expect(b.classes()).toContain('h-10');
      expect(b.classes()).toContain('min-h-11');
    });
    botoes.forEach(b =>
      expect(b.classes().join(' ')).toContain('bg-n-slate-9/10')
    );
    expect(botoes[0].attributes('aria-label')).toBe(
      'Mudar para onde vai a coluna Aniversário'
    );
    expect(linha.classes()).toContain('flex-wrap');
  });
});

describe('o título de "O que vou guardar"', () => {
  it('título do tamanho dos outros, botão no h2 e apoio quando fechado', async () => {
    const w = mount(OQueVouGuardar, {
      props: { colunas: leitura.colunas },
    });
    const botaoTitulo = w.get('h2 button');
    expect(w.get('h2').classes()).toEqual(
      expect.arrayContaining(['text-2xl', 'font-semibold'])
    );
    expect(botaoTitulo.classes()).toEqual(
      expect.arrayContaining(['text-2xl', 'font-semibold'])
    );
    expect(botaoTitulo.attributes('aria-expanded')).toBe('false');
    const apoio = marca(w, 'guardar-apoio');
    expect(apoio.text()).toBe(
      'Cada coluna da sua planilha e para onde ela vai.'
    );
    await botaoTitulo.trigger('click');
    expect(botaoTitulo.attributes('aria-expanded')).toBe('true');
    expect(marca(w, 'guardar-apoio').attributes('style') || '').toContain(
      'display: none'
    );
  });
});

describe('alinhamento à borda esquerda dos outros blocos', () => {
  it('o botão do título não tem padding próprio', () => {
    const w = mount(OQueVouGuardar, { props: { colunas: leitura.colunas } });
    expect(w.get('h2 button').classes()).toEqual(
      expect.arrayContaining(['p-0', 'min-h-11', 'bg-transparent', 'border-0'])
    );
  });
});
