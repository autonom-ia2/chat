import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import TelaPronto from '../../components/trazer/TelaPronto.vue';
// #2894 — o fim: a barra do andamento enquanto a lista é trazida e, quando
// termina, a frase inteira, a linha de sossego e a ação discreta.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

afterEach(() => {
  document.body.innerHTML = '';
});

describe('o andamento', () => {
  it('a largura da barra troca de uma vez, sem classe de transição', () => {
    const w = mount(TelaPronto, {
      props: { trazendo: true, porcentagem: 50 },
    });
    const barra = w.get('[role="progressbar"] > div');
    expect(barra.classes()).toContain('w-[50%]');
    expect(barra.classes().join(' ')).not.toContain('transition');
    expect(barra.classes().join(' ')).not.toContain('duration-');
    expect(barra.classes()).not.toContain('duration-500');
  });
});

describe('a linha de sossego', () => {
  it('Pronto cita o título novo', () => {
    const w = mount(TelaPronto, {
      props: { novas: 180, completadas: 15, temDesfazer: true },
    });
    expect(marca(w, 'pronto-sossego').text()).toBe(
      'Você pode desfazer quando quiser, aqui embaixo.'
    );
  });
});

describe('sem o Desfazer na conta', () => {
  it('o Pronto não promete desfazer: a linha de sossego não existe', () => {
    const w = mount(TelaPronto, { props: { novas: 180, completadas: 15 } });
    expect(marca(w, 'pronto').exists()).toBe(true);
    expect(marca(w, 'pronto-sossego').exists()).toBe(false);
    expect(w.text()).not.toContain('desfazer');
  });
});

describe('o Pronto', () => {
  it('linha de sossego abaixo do herói e "Trazer outra lista" discreta', () => {
    const w = mount(TelaPronto, {
      props: { novas: 180, completadas: 15, temDesfazer: true },
    });
    expect(marca(w, 'pronto').exists()).toBe(true);
    expect(marca(w, 'pronto-sossego').text()).toBe(
      'Você pode desfazer quando quiser, aqui embaixo.'
    );
    expect(marca(w, 'trazer-outra').text()).toBe('Trazer outra lista');
    expect(marca(w, 'trazer-outra').classes()).toContain('!bg-white/10');
    expect(marca(w, 'trazer-outra').classes()).toContain('rounded-lg');
  });
});

describe('a frase do Pronto nunca sai cortada', () => {
  it('é um texto só, que desce de linha equilibrado; a ação discreta não reserva a coluna do canto', () => {
    const w = mount(TelaPronto, { props: { novas: 180, completadas: 15 } });
    const titulo = w.get('[data-titulo-da-tela]');
    expect(titulo.text()).toBe('180 pessoas chegaram e 15 foram completadas.');
    expect(titulo.classes()).toContain('text-balance');
    // Nada dentro do título proíbe a quebra de linha (era o que cortava a frase).
    expect(titulo.html()).not.toContain('whitespace-nowrap');
    expect(titulo.findAll('*')).toHaveLength(0);
    expect(w.find('[data-heroi-discreta]').exists()).toBe(false);
    expect(
      marca(w, 'trazer-outra').element.closest('[data-heroi-acao]')
    ).not.toBeNull();
    expect(marca(w, 'trazer-outra').text()).toBe('Trazer outra lista');
  });
});
