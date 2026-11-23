import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import {
  fornecerConversaDaTela,
  useAnexosDaTela,
  useConversaDaTela,
  useSoLeitura,
} from '../conversaDaTela';

// #3165: sem quem forneça, vale a conversa aberta no painel; com, a fornecida e só leitura.
const lida = {};
const Leitor = defineComponent({
  setup() {
    lida.conversa = useConversaDaTela();
    lida.anexos = useAnexosDaTela();
    lida.soLeitura = useSoLeitura();
    return () => h('div');
  },
});
const loja = {
  getters: {
    getSelectedChat: { id: 1, inbox_id: 3 },
    getSelectedChatAttachments: [{ id: 'aberta' }],
  },
};
const comLoja = {
  install: app => {
    app.config.globalProperties.$store = loja;
  },
};
const montar = componente =>
  mount(componente, { global: { plugins: [comLoja] } });

describe('conversaDaTela', () => {
  it('sem fornecer, lê a conversa aberta do painel e não é só leitura', () => {
    montar(Leitor);
    expect(lida.conversa.value).toEqual({ id: 1, inbox_id: 3 });
    expect(lida.anexos.value).toEqual([{ id: 'aberta' }]);
    expect(lida.soLeitura.value).toBe(false);
  });

  it('com a conversa fornecida, lê essa e liga o só leitura', () => {
    const Tela = defineComponent({
      setup() {
        fornecerConversaDaTela({
          conversa: computed(() => ({ id: 94, inbox_id: 1 })),
          anexos: computed(() => [{ id: 'da-tela' }]),
        });
        return () => h(Leitor);
      },
    });
    montar(Tela);
    expect(lida.conversa.value).toEqual({ id: 94, inbox_id: 1 });
    expect(lida.anexos.value).toEqual([{ id: 'da-tela' }]);
    expect(lida.soLeitura.value).toBe(true);
  });
});
