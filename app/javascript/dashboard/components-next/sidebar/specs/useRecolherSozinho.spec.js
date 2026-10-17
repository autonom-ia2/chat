import { mount } from '@vue/test-utils';
import { computed, defineComponent, h, nextTick, reactive, ref } from 'vue';
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
  const route = reactive({
    name: tela,
    path: `/${tela}`,
    fullPath: `/${tela}`,
    params: {},
  });
  const janela = ref(1440);
  const raiz = ref(null);
  const sidebarWidth = ref(LARGURA_PADRAO);
  const uiSettings = ref({ ...salvo });
  const updateUISettings = vi.fn(novo => {
    uiSettings.value = { ...uiSettings.value, ...novo };
  });
  const isCollapsed = computed(() => sidebarWidth.value < 160);
  const telaDeTrabalho = computed(
    () => janela.value >= 768 && ehTelaDeTrabalho(route.name)
  );
  const restaurar = vi.fn();
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
          restaurar: () => {
            restaurar();
            largura.aplicar();
          },
          raiz,
        });
        return () =>
          h('div', { ref: raiz }, [h('button', { id: 'item' }, 'Item')]);
      },
    }),
    { attachTo: document.body }
  );
  const irPara = async nome => {
    route.name = nome;
    route.path = `/${nome}`;
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
    route,
    janela,
    restaurar,
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

  // Foco vindo do teclado: no jsdom o :focus-visible não existe, então o alvo diz que é.
  const focoDeTeclado = el => {
    el.matches = seletor => seletor === ':focus-visible';
    el.focus();
    return { target: el };
  };
  const atalho = () =>
    document.body.dispatchEvent(
      new KeyboardEvent('keydown', { key: '\\', ctrlKey: true, bubbles: true })
    );

  it('filtro do CRM (query) ou âncora (hash) na mesma tela não reinicia os 30 s', async () => {
    const { route, sidebarWidth, wrapper } = montar({
      tela: 'crm_kanban_index',
    });
    vi.advanceTimersByTime(20000);
    route.fullPath = '/crm_kanban_index?etapa=2#card-9';
    await nextTick();
    vi.advanceTimersByTime(10000);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('depois do clique, destino que não é de trabalho cancela: o menu nem pisca', async () => {
    const { api, sidebarWidth, irPara, wrapper } = montar();
    const larguras = [];
    const espia = setInterval(() => larguras.push(sidebarWidth.value), 50);
    api.depoisDoClique();
    vi.advanceTimersByTime(300);
    await irPara('settings_inicio');
    vi.advanceTimersByTime(5000);
    clearInterval(espia);
    expect(larguras).not.toContain(LARGURA_RECOLHIDA);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    wrapper.unmount();
  });

  it('depois do clique, quem decide é o destino: chegou depois dos 0,6 s numa tela de trabalho, recolhe ao chegar', async () => {
    const { api, sidebarWidth, irPara, wrapper } = montar({
      tela: 'settings_inicio',
    });
    api.depoisDoClique();
    vi.advanceTimersByTime(1500);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    await irPara('crm_calendar_index');
    vi.advanceTimersByTime(100);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('clicar na tela já aberta não deixa nada pendente: a próxima tela de trabalho conta 30 s', async () => {
    const { api, sidebarWidth, irPara, wrapper } = montar({
      tela: 'settings_inicio',
    });
    api.depoisDoClique();
    vi.advanceTimersByTime(4000);
    await irPara('crm_kanban_index');
    vi.advanceTimersByTime(1000);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('foco de teclado pausa; foco de clique não; sair do menu retoma', async () => {
    const { api, sidebarWidth, wrapper } = montar();
    const botao = document.getElementById('item');
    botao.matches = () => false;
    botao.focus();
    api.focoEntrou({ target: botao });
    vi.advanceTimersByTime(5000);
    expect(api.progresso.value).toBeLessThan(1);

    api.focoEntrou(focoDeTeclado(botao));
    const parado = api.progresso.value;
    vi.advanceTimersByTime(60000);
    expect(api.progresso.value).toBe(parado);

    const raiz = botao.parentElement;
    api.focoSaiu({ currentTarget: raiz, relatedTarget: botao });
    vi.advanceTimersByTime(60000);
    expect(api.progresso.value).toBe(parado);

    api.focoSaiu({ currentTarget: raiz, relatedTarget: document.body });
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('repro: Tab, Enter, recolhe, Ctrl+\\ reabre e a contagem volta', async () => {
    const { api, sidebarWidth, irPara, wrapper } = montar({
      tela: 'settings_inicio',
    });
    const botao = document.getElementById('item');
    api.focoEntrou(focoDeTeclado(botao));
    api.depoisDoClique();
    await irPara('inbox_conversation');
    vi.advanceTimersByTime(TEMPO_APOS_CLIQUE);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    botao.remove();
    await nextTick();

    atalho();
    await nextTick();
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    expect(api.progresso.value).toBe(1);
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('foco num item que saiu da tela não pausa a contagem', () => {
    const { api, sidebarWidth, wrapper } = montar();
    const botao = document.getElementById('item');
    api.focoEntrou(focoDeTeclado(botao));
    botao.remove();
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });

  it('Ctrl+\\ em tela de trabalho recolhe e abre sem gravar a preferência', async () => {
    const { sidebarWidth, updateUISettings, wrapper } = montar({
      salvo: { sidebar_width: 256 },
    });
    atalho();
    await nextTick();
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    atalho();
    await nextTick();
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);
    expect(updateUISettings).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('cruzar 768 px numa tela de trabalho reavalia o relógio', async () => {
    const { api, janela, restaurar, sidebarWidth, wrapper } = montar();
    vi.advanceTimersByTime(10000);
    janela.value = 700;
    await nextTick();
    expect(restaurar).toHaveBeenCalledTimes(1);
    expect(api.progresso.value).toBe(0);
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_PADRAO);

    janela.value = 1440;
    await nextTick();
    expect(api.progresso.value).toBe(1);
    vi.advanceTimersByTime(TEMPO_ABERTO);
    expect(sidebarWidth.value).toBe(LARGURA_RECOLHIDA);
    wrapper.unmount();
  });
});
