import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import DialogoDesfazer from '../../components/trazer/DialogoDesfazer.vue';
// #2894 — o diálogo do Desfazer: o título com o nome da lista e o item de
// quem fica (a prévia é uma lista: quem sai, quem fica e quem volta).
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

  it('o item de quem fica aparece só com ficam > 0, entre quem sai e quem volta', () => {
    const com = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 162, ficam: 18, devolve: 15 },
    });
    const chaves = w =>
      w.findAll('[data-linha]').map(item => item.attributes('data-linha'));
    expect(chaves(com)).toEqual(['saem', 'ficam', 'voltam']);
    const ficam = com.get('[data-linha="ficam"]').findAll('p');
    expect(ficam.map(linha => linha.text())).toEqual([
      '18 pessoas ficam',
      'Alguém já cuidou delas (conversa, card, etiqueta, campanha ou seguro) ou mudou a ficha delas depois da lista, elas vieram também em outra lista, ou a lista não foi trazida por esta tela e não dá para saber se alguém mexeu nelas.',
    ]);
    const sem = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 5, ficam: 0, devolve: 0 },
    });
    expect(chaves(sem)).toEqual(['saem']);
    expect(sem.get('[data-linha="saem"]').findAll('p')[0].text()).toBe(
      '5 pessoas saem'
    );
    expect(marca(sem, 'dialogo-desfazer').text()).not.toContain('ficam');
    expect(marca(sem, 'dialogo-desfazer').text()).not.toContain(' fica');
  });

  it('com as três contagens em zero, a frase de que falta só terminar no lugar da lista', () => {
    const w = montar({
      arquivo: 'a.xlsx',
      previa: { tira: 0, ficam: 0, devolve: 0 },
    });
    expect(marca(w, 'desfazer-previa').exists()).toBe(false);
    expect(w.findAll('[data-linha]')).toHaveLength(0);
    expect(marca(w, 'desfazer-nada').text()).toBe(
      'Ninguém mais sai. Falta só terminar.'
    );
    expect(w.findAll('button').map(b => b.text())).toEqual([
      'Cancelar',
      'Desfazer',
    ]);
  });

  // Regra do dono: nenhum botão desligado por falta de dado.
  describe('o botão de desfazer', () => {
    const PREVIA = { tira: 5, ficam: 0, devolve: 0 };

    it('enquanto a prévia não chega, não está na tela: só o esqueleto e o botão de sair', () => {
      const w = montar({ arquivo: 'a.xlsx', previa: null });
      expect(w.findAll('.animate-pulse').length).toBeGreaterThan(0);
      expect(marca(w, 'desfazer-confirmar').exists()).toBe(false);
      expect(w.findAll('button').map(b => b.text())).toEqual(['Cancelar']);
      expect(w.find('button[disabled]').exists()).toBe(false);
    });

    it('com a prévia na tela, aparece ligado', () => {
      const w = montar({ arquivo: 'a.xlsx', previa: PREVIA });
      const confirmar = marca(w, 'desfazer-confirmar');
      expect(confirmar.text()).toBe('Desfazer');
      expect(confirmar.attributes('disabled')).toBeUndefined();
    });

    it('durante o pedido mostra que está trabalhando, sem ficar desligado', () => {
      const w = montar({ arquivo: 'a.xlsx', previa: PREVIA, desfazendo: true });
      const confirmar = marca(w, 'desfazer-confirmar');
      expect(confirmar.find('svg.animate-spin').exists()).toBe(true);
      expect(confirmar.attributes('aria-busy')).toBe('true');
      expect(confirmar.attributes('disabled')).toBeUndefined();
      expect(w.find('button[disabled]').exists()).toBe(false);
    });
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
      expect(marca(w, 'desfazer-previa').exists()).toBe(false);
      expect(marca(w, 'desfazer-nada').exists()).toBe(false);
      expect(w.findAll('[data-linha]')).toHaveLength(0);
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
