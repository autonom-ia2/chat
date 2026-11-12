import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';
// #2894 — o diálogo do Desfazer: o título com o nome da lista e a frase de
// quem fica.
// #2896 — a lista que o servidor ainda não deixa desfazer (`naoPode`): o
// diálogo diz por quê, como alerta e com o foco nele, e fica só o botão de sair.
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
      '18 ficam aqui: alguém já cuidou delas (conversa, card, etiqueta ou campanha) ou elas vieram também em outra lista.'
    );
    const sem = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 5, ficam: 0, devolve: 0 },
    });
    expect(marca(sem, 'dialogo-desfazer').text()).not.toContain('ficam aqui');
    expect(marca(sem, 'dialogo-desfazer').text()).not.toContain(' fica aqui');
  });

  describe('a lista que ainda não dá para desfazer', () => {
    const NAO_PODE =
      'Esta lista ainda está sendo trazida. Quando terminar, você pode desfazer.';
    const PREVIA = { tira: 162, ficam: 18, devolve: 15 };

    it('diz por quê num alerta, no lugar da prévia, e tira o botão de desfazer', () => {
      const w = montar({ arquivo: 'a.xlsx', previa: PREVIA, naoPode: true });
      const alerta = marca(w, 'desfazer-nao-pode');
      expect(alerta.text()).toBe(NAO_PODE);
      expect(alerta.attributes('role')).toBe('alert');
      expect(marca(w, 'dialogo-desfazer').text()).not.toContain('Isto tira');
      expect(marca(w, 'desfazer-confirmar').exists()).toBe(false);
      // Sobra uma ação só: sair. Nenhum botão desligado.
      const botoes = w.findAll('button');
      expect(botoes.map(b => b.text())).toEqual(['Cancelar']);
      expect(botoes[0].attributes('disabled')).toBeUndefined();
    });

    it('a recusa veio já na prévia: o alerta, sem esqueleto nem "tentar de novo"', () => {
      const w = montar({ arquivo: 'a.xlsx', previa: null, naoPode: true });
      expect(marca(w, 'desfazer-nao-pode').text()).toBe(NAO_PODE);
      expect(w.findAll('.animate-pulse')).toHaveLength(0);
      expect(w.findAll('button').map(b => b.text())).toEqual(['Cancelar']);
    });

    it('quando a recusa chega, o foco vai para o alerta', async () => {
      const w = mount(DialogoDesfazer, {
        props: { arquivo: 'a.xlsx', previa: PREVIA },
        attachTo: document.body,
        global: { stubs: { Dialog: DialogFalso } },
      });
      expect(marca(w, 'desfazer-nao-pode').exists()).toBe(false);
      await w.setProps({ naoPode: true });
      expect(document.activeElement).toBe(
        marca(w, 'desfazer-nao-pode').element
      );
      w.unmount();
    });
  });
});
