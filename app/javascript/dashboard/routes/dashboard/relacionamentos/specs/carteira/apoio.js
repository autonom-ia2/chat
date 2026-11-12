import { defineComponent, h, ref } from 'vue';
import { flushPromises } from '@vue/test-utils';

// Apoio dos testes da carteira (#2897).

// O <dialog> do jsdom não tem showModal: nos testes o Dialog da casa vira esta
// peça, com o mesmo contrato (`open()`, `close()`, `confirm`, `close`). Quando
// quem usa manda o rodapé (slot `footer`), é ele que aparece; senão, os dois
// botões de sempre. O conteúdo só existe enquanto está aberto.
export const DialogoFalso = defineComponent({
  name: 'DialogoFalso',
  props: {
    confirmButtonLabel: { type: String, default: '' },
    cancelButtonLabel: { type: String, default: '' },
    showCancelButton: { type: Boolean, default: true },
  },
  emits: ['confirm', 'close'],
  setup(props, { emit, slots, expose }) {
    const aberto = ref(false);
    const close = () => {
      emit('close');
      aberto.value = false;
    };
    expose({
      open: () => {
        aberto.value = true;
      },
      close,
    });
    const botoesDeSempre = () => [
      props.showCancelButton
        ? h(
            'button',
            { type: 'button', 'data-cancelar': '', onClick: close },
            props.cancelButtonLabel
          )
        : null,
      h(
        'button',
        {
          type: 'button',
          'data-confirmar': '',
          onClick: () => emit('confirm'),
        },
        props.confirmButtonLabel
      ),
    ];
    // Como no de verdade, o botão de enviar do rodapé confirma o diálogo.
    const aoEnviar = evento => {
      evento.preventDefault();
      emit('confirm');
    };
    return () =>
      aberto.value
        ? h('form', { 'data-dialogo-falso': '', onSubmit: aoEnviar }, [
            slots.default?.(),
            slots.footer ? slots.footer() : botoesDeSempre(),
          ])
        : null;
  },
});

// A gaveta e o diálogo vão para o <body>; nos testes ficam no lugar.
export { TeleportFalso } from '../lista/teleportFalso';

export const daCarteira = nome => `[data-carteira="${nome}"]`;
export const doBlocoA = nome => `[data-relacionamentos="${nome}"]`;

// A fonte de demonstração espera em setTimeout: com o relógio falso o tempo é
// nosso, e a máquina carregada não muda o resultado.
export const assentar = async () => {
  await vi.advanceTimersByTimeAsync(40);
  await flushPromises();
};

// As fontes carregam os dados por import() dinâmico, que leva tempo de verdade.
// Carregar antes deixa as respostas só por conta do relógio falso.
export const carregarDemonstracao = () =>
  Promise.all([
    import('../../demo/base.js'),
    import('../../demo/carteira.js'),
    import('../../demo/carteiraRenovacao.js'),
    import('../../demo/carteiraAjustes.js'),
    import('../../demo/carteiraResultados.js'),
    import('../../demo/ficha.js'),
    import('../../demo/acoesDaLista.js'),
  ]);

// O <ul> das opções rola até a escolhida; o jsdom não tem `scrollIntoView`.
export const semRolagem = () => {
  HTMLElement.prototype.scrollIntoView ??= () => {};
};

export const textoDe = (w, seletor) =>
  w.get(seletor).text().split(' ').join(' ');
