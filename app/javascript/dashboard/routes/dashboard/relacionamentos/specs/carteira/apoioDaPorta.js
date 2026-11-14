import { flushPromises, mount, RouterLinkStub } from '@vue/test-utils';
import TrazerPage from '../../pages/TrazerPage.vue';
import { DialogFalso } from '../trazer/apoioDaPagina';

// Apoio dos specs de "Trazer minha lista" pela porta dela (pages/TrazerPage.vue,
// #2897), que é o que a rota abre: na conta de seguros ela baixa o que os
// seguros pedem antes de mostrar a tela. Os `vi.mock` ficam em cada spec.
export const abrirAPorta = async (props = {}) => {
  const w = mount(TrazerPage, {
    attachTo: document.body,
    props,
    global: { stubs: { RouterLink: RouterLinkStub, Dialog: DialogFalso } },
  });
  await flushPromises();
  return w;
};
