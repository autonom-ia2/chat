import { mount } from '@vue/test-utils';
import LivreSeletorPasso from '../components/LivreSeletorPasso.vue';

// G13 (#2670) — o passo que pede uma permissão (`chave`) só aparece no seletor
// para quem a tem; o servidor recusa do mesmo jeito ao salvar.
const catalogo = {
  grupos: [
    { chave: 'CONTROLE', frase: 'G.CONTROLE' },
    { chave: 'OUTRO_SISTEMA', frase: 'G.OUTRO' },
  ],
  passos: [
    { tipo: 'esperar', grupo: 'CONTROLE', frase: 'P.ESPERAR' },
    {
      tipo: 'webhook',
      grupo: 'OUTRO_SISTEMA',
      chave: 'integration_manage',
      frase: 'P.WEBHOOK',
    },
  ],
};

const montar = temChave =>
  mount(LivreSeletorPasso, {
    props: { catalogo, liberado: () => true, temChave },
    global: {
      mocks: { $t: chave => chave },
      stubs: { SidePanel: { template: '<div><slot /></div>' } },
    },
  });

describe('LivreSeletorPasso', () => {
  it('sem a chave de integrações, o webhook e o grupo dele somem', () => {
    const wrapper = montar(() => false);
    expect(wrapper.find('[data-grupo="OUTRO_SISTEMA"]').exists()).toBe(false);
    expect(wrapper.find('[data-grupo="CONTROLE"]').exists()).toBe(true);
  });

  it('com a chave, o webhook aparece', () => {
    const wrapper = montar(chave => chave === 'integration_manage');
    expect(wrapper.find('[data-grupo="OUTRO_SISTEMA"]').exists()).toBe(true);
  });
});
