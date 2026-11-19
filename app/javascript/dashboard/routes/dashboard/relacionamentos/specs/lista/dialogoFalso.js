import { defineComponent, h, ref } from 'vue';

// O <dialog> do jsdom não tem showModal: nos testes o Dialog da casa vira esta
// peça simples, com o mesmo contrato (props, `open()`, `close()`, `confirm` e
// `close`). O conteúdo só existe enquanto está aberto, como o de verdade.
export const DialogoFalso = defineComponent({
  name: 'DialogoFalso',
  props: {
    title: { type: String, default: '' },
    description: { type: String, default: '' },
    confirmButtonLabel: { type: String, default: '' },
    cancelButtonLabel: { type: String, default: '' },
    showCancelButton: { type: Boolean, default: true },
    disableConfirmButton: { type: Boolean, default: false },
    isLoading: { type: Boolean, default: false },
    closeOnOutsideClick: { type: Boolean, default: true },
    type: { type: String, default: 'edit' },
    width: { type: String, default: 'lg' },
  },
  emits: ['confirm', 'close'],
  setup(props, { emit, slots, expose }) {
    const aberto = ref(false);
    const open = () => {
      aberto.value = true;
    };
    const close = () => {
      emit('close');
      aberto.value = false;
    };
    expose({ open, close });
    const confirmar = () => emit('confirm');
    // O rodapé próprio de quem usa (#footer) toma o lugar dos dois botões,
    // como no de verdade, e mora num <form>: o botão `type="submit"` dele
    // confirma.
    const botoes = () => [
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
          disabled: props.disableConfirmButton,
          onClick: confirmar,
        },
        props.confirmButtonLabel
      ),
    ];
    const rodape = () =>
      slots.footer
        ? [
            h(
              'form',
              {
                'data-rodape-proprio': '',
                onSubmit: evento => {
                  evento.preventDefault();
                  confirmar();
                },
              },
              slots.footer()
            ),
          ]
        : botoes();
    return () =>
      aberto.value
        ? h(
            'div',
            {
              'data-dialogo-falso': '',
              'data-fechar-fora': String(props.closeOnOutsideClick),
              'data-tipo': props.type,
              'data-largura': props.width,
              'data-carregando': String(props.isLoading),
            },
            [
              props.title ? h('h3', props.title) : null,
              props.description ? h('p', props.description) : null,
              slots.default?.(),
              ...rodape(),
            ]
          )
        : null;
  },
});
