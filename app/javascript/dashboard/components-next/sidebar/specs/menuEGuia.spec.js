import { mount } from '@vue/test-utils';
import { defineComponent, nextTick, ref } from 'vue';
import { menuEGuia, useMenuRecolheComOGuia } from '../menuEGuia';

// #3184 — o menu recolhe quando o Guia abre, sem gravar preferência.
const montar = ({ largura = 256, celular = false } = {}) => {
  const sidebarWidth = ref(largura);
  const isCollapsed = ref(largura < 160);
  const ehCelular = ref(celular);
  mount(
    defineComponent({
      setup() {
        useMenuRecolheComOGuia({
          sidebarWidth,
          isCollapsed,
          celular: ehCelular,
        });
        return () => null;
      },
    })
  );
  return { sidebarWidth, ehCelular };
};

describe('useMenuRecolheComOGuia (#3184)', () => {
  afterEach(() => {
    menuEGuia.guiaAberto.value = false;
    menuEGuia.largura.value = 0;
    menuEGuia.devolvida.value = 0;
  });

  it('publica a largura do menu, e zero no celular', async () => {
    const { sidebarWidth, ehCelular } = montar();
    expect(menuEGuia.largura.value).toBe(256);

    sidebarWidth.value = 200;
    await nextTick();
    expect(menuEGuia.largura.value).toBe(200);

    ehCelular.value = true;
    await nextTick();
    expect(menuEGuia.largura.value).toBe(0);
  });

  it('abrir o Guia recolhe o menu', async () => {
    const { sidebarWidth } = montar();

    menuEGuia.guiaAberto.value = true;
    await nextTick();

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(200);
  });

  it('carregar a página com o Guia aberto recolhe o menu', () => {
    menuEGuia.guiaAberto.value = true;

    const { sidebarWidth } = montar({ largura: 200 });

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(144);
  });

  it('fechar o Guia não reabre o menu', async () => {
    menuEGuia.guiaAberto.value = true;
    const { sidebarWidth } = montar();

    menuEGuia.guiaAberto.value = false;
    await nextTick();

    expect(sidebarWidth.value).toBe(56);
  });
});
