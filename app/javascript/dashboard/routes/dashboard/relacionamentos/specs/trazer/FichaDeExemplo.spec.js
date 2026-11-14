import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import { leituraDeExemplo } from '../../demo/trazer';
import FichaDeExemplo from '../../components/trazer/FichaDeExemplo.vue';
// #2894 — a ficha de exemplo do Conferir ("Como vão ficar"): o nome inteiro em
// até duas linhas, o selo na coluna do nome e o e-mail que só quebra no "@".
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const leitura = leituraDeExemplo('l1');

afterEach(() => {
  document.body.innerHTML = '';
});

describe('nome inteiro na ficha', () => {
  it('o nome não trunca e reserva duas linhas em md+', async () => {
    const { default: Ficha } = await import(
      '../../components/trazer/FichaDeExemplo.vue'
    );
    const w = mount(Ficha, {
      props: { pessoa: { ...leitura.exemplos[1], cliente: true } },
    });
    const nome = w.get('h3');
    expect(nome.classes()).toEqual(
      expect.arrayContaining(['line-clamp-2', 'md:min-h-12'])
    );
    expect(nome.classes()).not.toContain('md:truncate');
  });
});

describe('nome inteiro, selo embaixo', () => {
  const pessoa = {
    nome: 'Marina Esteveira',
    telefone: '+55 11 94271-0003',
    email: 'marina.esteveira@exemplo.com.br',
    empresa: '',
    cliente: true,
  };

  it('o nome não é cortado e o selo fica na coluna do nome', () => {
    const w = mount(FichaDeExemplo, { props: { pessoa } });
    const nome = w.get('h3');
    expect(nome.classes()).not.toContain('truncate');
    expect(
      nome.element.parentElement.contains(w.get('[data-selo]').element)
    ).toBe(true);
  });

  it('o e-mail tem title com o endereço inteiro', () => {
    const w = mount(FichaDeExemplo, { props: { pessoa } });
    expect(w.find(`[title="${pessoa.email}"]`).exists()).toBe(true);
  });
});

describe('o e-mail e o nome da ficha', () => {
  it('o e-mail da ficha quebra em até duas linhas, sem truncar', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Marina Esteveira',
          telefone: '+55 11 94271-0003',
          email: 'marina.esteveira@exemplo.com.br',
          empresa: '',
          cliente: false,
        },
      },
    });
    const email = w.get('[title="marina.esteveira@exemplo.com.br"]');
    expect(email.classes()).toEqual(
      expect.arrayContaining(['break-words', 'line-clamp-2'])
    );
    expect(email.classes()).not.toContain('break-all');
    expect(email.classes()).not.toContain('truncate');
  });

  it('o e-mail só quebra no "@", com <wbr> entre as duas partes', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Marina Esteveira',
          telefone: '',
          email: 'marina.esteveira@exemplo.com.br',
          empresa: '',
          cliente: false,
        },
      },
    });
    const email = w.get('[title="marina.esteveira@exemplo.com.br"]');
    expect(email.element.innerHTML).toContain(
      'marina.esteveira<wbr>@exemplo.com.br'
    );
    expect(email.text()).toBe('marina.esteveira@exemplo.com.br');
  });

  it('e-mail sem "@" (linha com problema) vem inteiro, sem <wbr>', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Rita Carvalhedo',
          telefone: '',
          email: 'rita.carvalhedo.exemplo.com.br',
          empresa: '',
          cliente: false,
        },
      },
    });
    const email = w.get('[title="rita.carvalhedo.exemplo.com.br"]');
    expect(email.element.innerHTML).not.toContain('<wbr>');
    expect(email.text()).toBe('rita.carvalhedo.exemplo.com.br');
  });

  it('nome em até 2 linhas, com altura reservada em md+ (selo alinhado)', () => {
    const w = mount(FichaDeExemplo, {
      props: {
        pessoa: {
          nome: 'Otávio Lourenzatto',
          telefone: '',
          email: '',
          empresa: '',
          cliente: true,
        },
      },
    });
    const nome = w.get('h3');
    expect(nome.classes()).toEqual(
      expect.arrayContaining(['line-clamp-2', 'md:min-h-12'])
    );
    expect(nome.classes()).not.toContain('md:truncate');
    expect(nome.attributes('title')).toBe('Otávio Lourenzatto');
  });
});
