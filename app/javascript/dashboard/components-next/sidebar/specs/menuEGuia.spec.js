import { mount } from '@vue/test-utils';
import { computed, defineComponent, nextTick, ref } from 'vue';
import { menuEGuia, useMenuRecolheComOGuia } from '../menuEGuia';

// #3184 — o menu recolhe quando o Guia abre, sem gravar preferência.
const montar = ({ largura = 256, celular = false } = {}) => {
  const sidebarWidth = ref(largura);
  const isCollapsed = computed(() => sidebarWidth.value < 160);
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
    menuEGuia.copilotoAberto.value = false;
    menuEGuia.largura.value = 0;
    menuEGuia.devolvida.value = 0;
    menuEGuia.recolhidoPeloGuia.value = false;
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

  it('menu reaberto com o Guia aberto: não recolhe de novo e não devolve mais nada', async () => {
    menuEGuia.guiaAberto.value = true;
    const { sidebarWidth } = montar();
    await nextTick();
    expect(menuEGuia.devolvida.value).toBe(200);

    sidebarWidth.value = 256;
    await nextTick();

    expect(sidebarWidth.value).toBe(256);
    expect(menuEGuia.devolvida.value).toBe(0);
    expect(menuEGuia.largura.value).toBe(256);
  });

  it('abrir, fechar e abrir o Guia: a largura devolvida continua', async () => {
    const { sidebarWidth } = montar();
    menuEGuia.guiaAberto.value = true;
    await nextTick();
    menuEGuia.guiaAberto.value = false;
    await nextTick();
    menuEGuia.guiaAberto.value = true;
    await nextTick();

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(200);
  });

  it('menu já recolhido antes do Guia: nada devolvido, mesmo com valor antigo', () => {
    menuEGuia.devolvida.value = 200;
    menuEGuia.guiaAberto.value = true;

    montar({ largura: 56 });

    expect(menuEGuia.devolvida.value).toBe(0);
  });

  it('do celular para o computador com o Guia aberto: recolhe o menu', async () => {
    menuEGuia.guiaAberto.value = true;
    const { sidebarWidth, ehCelular } = montar({ celular: true });
    expect(sidebarWidth.value).toBe(256);

    ehCelular.value = false;
    await nextTick();

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(200);
  });

  it('abrir o Copiloto da equipe também recolhe o menu (#3191)', async () => {
    const { sidebarWidth } = montar();

    menuEGuia.copilotoAberto.value = true;
    await nextTick();

    expect(sidebarWidth.value).toBe(56);
    expect(menuEGuia.devolvida.value).toBe(200);
  });
});
