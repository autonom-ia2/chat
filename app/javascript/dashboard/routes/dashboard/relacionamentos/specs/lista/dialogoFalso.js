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
                  onClick: () => emit('confirm'),
                },
                props.confirmButtonLabel
              ),
            ]
          )
        : null;
  },
});

// A gaveta e o diálogo vão para o <body>; nos testes ficam no lugar.
export const TeleportFalso = defineComponent({
  name: 'TeleportFalso',
  setup(_, { slots }) {
    return () => h('div', slots.default?.());
  },
});
