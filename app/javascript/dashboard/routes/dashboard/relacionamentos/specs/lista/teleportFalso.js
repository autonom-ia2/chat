import { defineComponent, h } from 'vue';

// A gaveta e o diálogo vão para o <body>; nos testes ficam no lugar.
export const TeleportFalso = defineComponent({
  name: 'TeleportFalso',
  setup(_, { slots }) {
    return () => h('div', slots.default?.());
  },
});
