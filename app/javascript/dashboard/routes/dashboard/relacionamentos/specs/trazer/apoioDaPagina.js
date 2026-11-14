import { expect, vi } from 'vitest';
import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import TrazerListaPage from '../../pages/TrazerListaPage.vue';

// Apoio dos specs da página "Trazer minha lista" inteira
// (pages/TrazerListaPage.vue): montar a página, achar as marcas dela, esperar
// uma tela aparecer e andar do link de exemplo até o Conferir. Os `vi.mock`
// ficam em cada spec (o vitest os sobe para o topo do arquivo que os declara).
export const DialogFalso = {
  props: ['title'],
  emits: ['close', 'confirm'],
  methods: {
    open() {
      this.aberto = true;
    },
    close() {
      this.aberto = false;
      this.$emit('close');
    },
  },
  data: () => ({ aberto: false }),
  template: `<form v-if="aberto" data-dialog @submit.prevent="$emit('confirm')"><h3>{{ title }}</h3><slot /><slot name="footer" /></form>`,
};

export const erroHttp = (status, data = {}) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    response: { status, data },
  });

export const marca = (w, nome) => w.find(`[data-relacionamentos="${nome}"]`);

export const botao = (w, texto) =>
  w.findAll('button').find(b => b.text() === texto);

// Espera por condição, com folga para máquina carregada (o padrão é 1 s).
export const esperarPor = (verificacao, opcoes) =>
  vi.waitFor(verificacao, { timeout: 5000, ...opcoes });

export const aparece = (w, nome) =>
  esperarPor(() => expect(marca(w, nome).exists()).toBe(true));

export const some = (w, nome) =>
  esperarPor(() => expect(marca(w, nome).exists()).toBe(false));

export const abrir = async () => {
  const w = mount(TrazerListaPage, {
    attachTo: document.body,
    global: { stubs: { RouterLink: RouterLinkStub, Dialog: DialogFalso } },
  });
  await flushPromises();
  return w;
};

export const escolher = async (w, resposta) => {
  await marca(w, 'pergunta')
    .get(`[data-resposta="${resposta}"]`)
    .trigger('click');
};

export const continuar = async w => {
  await marca(w, 'continuar').trigger('click');
};

// Do link de exemplo até a tela Conferir.
export const irAteConferir = async w => {
  await marca(w, 'usar-exemplo').trigger('click');
  await aparece(w, 'pergunta');
  await escolher(w, 'sim_todas');
  await continuar(w);
  await esperarPor(() =>
    expect(marca(w, 'pergunta').attributes('data-pergunta')).toBe('telefone')
  );
  await escolher(w, 'da_pessoa');
  await continuar(w);
  await aparece(w, 'conferir');
};
