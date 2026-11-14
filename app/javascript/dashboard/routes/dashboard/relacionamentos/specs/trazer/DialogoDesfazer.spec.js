import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';
// #2894 — o diálogo do Desfazer: o título com o nome da lista e a frase de
// quem fica.
withFullI18n('pt_BR');

vi.setConfig({ testTimeout: 30000 });

const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

afterEach(() => {
  document.body.innerHTML = '';
});

describe('diálogo Desfazer', () => {
  const DialogFalso = {
    props: ['title'],
    template:
      '<div data-dialog><h3>{{ title }}</h3><slot /><slot name="footer" /></div>',
  };
  const montar = props =>
    mount(DialogoDesfazer, {
      props,
      global: { stubs: { Dialog: DialogFalso } },
    });

  it('o título diz o nome da lista', () => {
    const w = montar({
      arquivo: 'Clientes 2025.xlsx',
      previa: { tira: 1, ficam: 0, devolve: 0 },
    });
    expect(w.get('[data-relacionamentos="titulo-do-dialogo"]').text()).toBe(
      'Desfazer “Clientes 2025.xlsx”?'
    );
  });

  it('sem nome volta ao título geral', () => {
    const w = montar({ previa: null });
    expect(w.get('[data-relacionamentos="titulo-do-dialogo"]').text()).toBe(
      'Desfazer esta lista?'
    );
  });

  it('a frase de quem fica aparece só com ficam > 0, e ninguém sai prometendo conversa', () => {
    const com = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 162, ficam: 18, devolve: 15 },
    });
    const texto = marca(com, 'dialogo-desfazer').text();
    expect(texto).toContain(
      '18 ficam aqui, porque já conversaram com você ou já receberam campanha.'
    );
    const sem = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 5, ficam: 0, devolve: 0 },
    });
    expect(marca(sem, 'dialogo-desfazer').text()).not.toContain('ficam aqui');
    expect(marca(sem, 'dialogo-desfazer').text()).not.toContain(' fica aqui');
  });
});
