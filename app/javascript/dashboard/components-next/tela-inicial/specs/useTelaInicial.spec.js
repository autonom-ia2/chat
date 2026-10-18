import { ref } from 'vue';
import { useTelaInicial } from '../useTelaInicial';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

// #1801 — cada número leva à lista que ele conta, e a aba só vai depois da navegação
// (o ChatList reescreve a aba no mesmo ciclo da troca de rota).
const ordem = [];
const push = vi.fn(async destino => {
  ordem.push(`rota:${destino.name}`);
});

vi.mock('vue-router', () => ({ useRouter: () => ({ push }) }));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: nome =>
    nome === 'accounts/getAccount'
      ? ref(() => ({ name: 'Acme', timezone: 'America/Sao_Paulo' }))
      : ref(7),
}));
vi.mock('../useResumoDoServidor', () => ({
  useResumoDoServidor: () => ({
    resumo: ref({
      comVoce: 3,
      esperamVoce: 0,
      semResponsavel: 2,
      foraDoPrazo: null,
      proxima: null,
      equipe: null,
    }),
    estado: ref('pronto'),
    atualizar: vi.fn(),
  }),
}));

describe('useTelaInicial: para onde cada número leva', () => {
  const abas = [];
  const ouvir = aba => {
    ordem.push(`aba:${aba}`);
    abas.push(aba);
  };

  beforeEach(() => {
    ordem.length = 0;
    abas.length = 0;
    push.mockClear();
    emitter.on(BUS_EVENTS.TELA_INICIAL_ABA, ouvir);
  });
  afterEach(() => emitter.off(BUS_EVENTS.TELA_INICIAL_ABA, ouvir));

  it.each([
    ['verEsperam', 'conversation_unattended', 'me'],
    ['verSemResponsavel', 'home', 'unassigned'],
    ['verTodas', 'home', 'all'],
    ['verEquipe', 'conversation_unattended', 'all'],
  ])('%s: %s na aba %s, aba depois da rota', async (acao, rota, aba) => {
    await useTelaInicial()[acao]();
    expect(push).toHaveBeenCalledWith({ name: rota, params: { accountId: 7 } });
    expect(ordem).toEqual([`rota:${rota}`, `aba:${aba}`]);
  });

  it('em dia sem ninguém esperando; a ação do vazio vai às sem responsável', () => {
    const dados = useTelaInicial();
    expect(dados.tudoEmDia.value).toBe(true);
    expect(dados.acaoDoVazio.value.rotulo).toBe('VER_SEM_RESPONSAVEL');
    expect(dados.comVoce.value).toBe(3);
  });
});
