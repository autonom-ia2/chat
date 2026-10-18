import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import DialogoPerdeu from '../DialogoPerdeu.vue';

// #1802 — o diálogo de "não deu certo" usa o nome próprio do desfecho também
// em venda (Renovação: "Não renovou"); sem nome próprio, fica como hoje.
const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  missingWarn: false,
  fallbackWarn: false,
  messages: {
    pt_BR: {
      CRM_CARD: {
        CANCELAR: 'Cancelar',
        DESFECHO: {
          PERDEU_TITULO: 'Este negócio não deu certo?',
          PERDEU_TEXTO: 'Contar o motivo ajuda.',
          PERDEU_CONFIRMA: 'Marcar como perdido',
          PERDEU_TITULO_ROTULO: '{rotulo}: o que houve?',
          PERDEU_CONFIRMA_ROTULO: 'Marcar: {rotulo}',
          MOTIVO_ROTULO: 'Motivo',
          MOTIVO: {
            PRECO: 'Achou caro',
            SUMIU: 'Parou de responder',
            OUTRO_LUGAR: 'Fechou com outra corretora',
            NAO_ERA_HORA: 'A seguradora recusou',
          },
        },
      },
    },
  },
});

const DialogStub = {
  props: ['title', 'description'],
  template:
    '<div><h2 data-titulo>{{ title }}</h2><slot /><slot name="footer" /></div>',
};
const ButtonStub = {
  props: ['label'],
  template: '<button data-botao>{{ label }}</button>',
};

const montar = props =>
  mount(DialogoPerdeu, {
    props: { rotulo: 'Não renovou', venda: true, ...props },
    global: {
      plugins: [i18n],
      stubs: { Dialog: DialogStub, Button: ButtonStub, TextArea: true },
    },
  });

describe('DialogoPerdeu', () => {
  it('a sale with its own outcome name says it in the title and the button', () => {
    const wrapper = montar({ padrao: false });
    expect(wrapper.get('[data-titulo]').text()).toBe(
      'Não renovou: o que houve?'
    );
    expect(wrapper.findAll('[data-botao]').at(-1).text()).toBe(
      'Marcar: Não renovou'
    );
    expect(
      wrapper.findAll('button[aria-pressed]').map(botao => botao.text())
    ).toEqual([
      'Achou caro',
      'Parou de responder',
      'Fechou com outra corretora',
      'A seguradora recusou',
    ]);
  });

  it('a sale without its own name keeps the texts of today', () => {
    const wrapper = montar({ rotulo: 'Perdeu' });
    expect(wrapper.get('[data-titulo]').text()).toBe(
      'Este negócio não deu certo?'
    );
    expect(wrapper.findAll('[data-botao]').at(-1).text()).toBe(
      'Marcar como perdido'
    );
  });
});
