import { mount } from '@vue/test-utils';
import { computed, defineComponent, nextTick, reactive, ref } from 'vue';
import {
  LARGURA_PADRAO,
  LARGURA_RECOLHIDA,
  useLarguraDoMenu,
} from '../fork/useLarguraDoMenu';
import {
  TEMPO_ABERTO,
  TEMPO_APOS_CLIQUE,
  ehTelaDeTrabalho,
  useRecolherSozinho,
} from '../fork/useRecolherSozinho';

// Recolher sozinho nas telas de trabalho (#1781): 30 s com barrinha, pausa com o mouse, "Abrir menu" conta de
// novo, clique num item de tela de trabalho recolhe em 0,6 s, e a escolha salva da pessoa fica intacta.
const montar = ({ tela = 'inbox_conversation', salvo = {} } = {}) => {
  window.innerWidth = 1440;
  const route = reactive({ name: tela, fullPath: `/${tela}`, params: {} });
  const sidebarWidth = ref(LARGURA_PADRAO);
  const uiSettings = ref({ ...salvo });
  const updateUISettings = vi.fn(novo => {
    uiSettings.value = { ...uiSettings.value, ...novo };
  });
  const isCollapsed = computed(() => sidebarWidth.value < 160);
  const telaDeTrabalho = computed(() => ehTelaDeTrabalho(route.name));
  let api;
  let largura;
  const wrapper = mount(
    defineComponent({
      setup() {
        largura = useLarguraDoMenu({
          sidebarWidth,
          isCollapsed,
          uiSettings,
          updateUISettings,
          telaDeTrabalho,
        });
        api = useRecolherSozinho({
          route,
          telaDeTrabalho,
          isCollapsed,
          recolher: largura.recolherSemSalvar,
          restaurar: largura.aplicar,
        });
        return () => null;
      },
    })
  );
  const irPara = async nome => {
    route.name = nome;
    route.fullPath = `/${nome}`;
    await nextTick();
  };
  return {
    wrapper,
    api,
    largura,
    sidebarWidth,
    uiSettings,
    updateUISettings,
    irPara,
  };
};

describe('useRecolherSozinho', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => vi.useRealTimers());

  it('conversa aberta: mostra a barra e recolhe em 30 s, sem gravar nada', () => {
    const { api, sidebarWidth, updateUISettings, wrapper } = montar({
      salvo: { sidebar_width: 256 },
    });
    expect(api.progresso.value).toBe(1);
    vi.advanceTimersByTime(TEMPO_ABERTO / 2);
    expect(api.progresso.value).toBeCloseTo(0.5, 1);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    vi.advanceTimersByTime(TEMPO_ABERTO / 2);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    expect(api.progresso.value).toBe(0);
    expect(updateUISettings).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('mouse dentro do menu pausa; ao sair, retoma de onde parou', () => {
    const { api, sidebarWidth, wrapper } = montar();
    vi.advanceTimersByTime(10000);
    api.entrar();
    vi.advanceTimersByTime(60000);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    api.sair();
    vi.advanceTimersByTime(19000);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    vi.advanceTimersByTime(1000);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('"Abrir menu" depois de recolher abre por mais 30 s, com a barra cheia', async () => {
    const { api, largura, sidebarWidth, wrapper } = montar();
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    await nextTick();
    largura.alternar();
    await nextTick();
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    expect(api.progresso.value).toBe(1);
    vi.advanceTimersByTime(TEMPO_ABERTO - 100);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    vi.advanceTimersByTime(100);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('tela que não é de trabalho não conta nem recolhe', () => {
    const { api, sidebarWidth, wrapper } = montar({ tela: 'settings_inicio' });
    expect(api.progresso.value).toBe(0);
    vi.advanceTimersByTime(TEMPO_ABERTO * 3);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    wrapper.unmount();
  });

  it('clicar num item que leva a uma tela de trabalho recolhe em 0,6 s; para outra tela, não', async () => {
    const { api, sidebarWidth, irPara, wrapper } = montar({
      tela: 'settings_inicio',
    });
    api.depoisDoClique();
    await irPara('crm_kanban_index');
    vi.advanceTimersByTime(TEMPO_APOS_CLIQUE - 100);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    vi.advanceTimersByTime(100);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);

    await irPara('settings_inicio');
    await nextTick();
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    api.depoisDoClique();
    await irPara('agent_reports_index');
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    wrapper.unmount();
  });

  it('a preferência salva fica intacta: recolhido sozinho volta aberto fora da tela de trabalho', async () => {
    const { sidebarWidth, uiSettings, updateUISettings, irPara, wrapper } =
      montar({ salvo: { sidebar_width: 290, menu_largura_aberta: 290 } });
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    await irPara('settings_inicio');
    expect(sidebarWidth.value).toBe(290);
    expect(updateUISettings).not.toHaveBeenCalled();
    expect(uiSettings.value).toEqual({
      sidebar_width: 290,
      menu_largura_aberta: 290,
    });
    wrapper.unmount();
  });

  it('quem deixou recolhido continua recolhido: nada conta ao entrar na conversa', async () => {
    const { api, sidebarWidth, wrapper } = montar({
      salvo: { sidebar_width: LARGURA_RECOLHIDA, menu_largura_aberta: 256 },
    });
    await nextTick();
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    expect(api.progresso.value).toBe(0);
    wrapper.unmount();
  });

  it('desmontar limpa o relógio', () => {
    const { sidebarWidth, wrapper } = montar();
    wrapper.unmount();
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    expect(vi.getTimerCount()).toBe(0);
  });
});
