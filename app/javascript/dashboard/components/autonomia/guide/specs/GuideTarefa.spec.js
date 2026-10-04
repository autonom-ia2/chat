import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideTarefa from '../GuideTarefa.vue';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, valores) => (valores ? `${key}:${JSON.stringify(valores)}` : key),
    te: key =>
      key.includes('SKIP.nao_encontrado') || key.includes('TABLES.contacts'),
    locale: ref('pt_BR'),
  }),
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { tarefa: vi.fn(), comandarTarefa: vi.fn() },
}));

// #936 — o cartão da tarefa longa: amostra, pausa de segurança, andamento e
// relatório, cada um com uma ação principal.
const tarefa = (extra = {}) => ({
  id: 9,
  status: 'amostra_pronta',
  descricao: 'Arrumar o nome dos contatos',
  total: 512,
  feitos: 0,
  falhas: 0,
  pulados: 0,
  lotes: 0,
  amostra: [
    {
      ref: 'ANA SILVA',
      antes: { name: 'ANA SILVA' },
      depois: { name: 'Ana Silva' },
    },
    { ref: 'BRUNO', pulado: 'nao_encontrado' },
  ],
  canario: {},
  nao_feitos: [],
  custo_estimado: 0.42,
  tempo_estimado: 600,
  jev_estimado: 0,
  desfazivel: false,
  desfazer_ate: null,
  ...extra,
});

const montar = props =>
  mount(GuideTarefa, {
    props: { tarefaId: 9, ...props },
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
      stubs: {
        Banner: { template: '<div data-banner><slot /></div>' },
        Button: {
          props: ['label', 'isLoading'],
          emits: ['click'],
          template: '<button @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

const botao = (wrapper, chave) =>
  wrapper.findAll('button').find(item => item.text() === chave);

describe('GuideTarefa', () => {
  beforeEach(() => vi.clearAllMocks());

  it('mostra que está carregando e depois a amostra', async () => {
    AutonomiaGuideAPI.tarefa.mockResolvedValue({ data: tarefa() });
    const wrapper = montar();

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.TASK.LOADING');
    await flushPromises();

    expect(AutonomiaGuideAPI.tarefa).toHaveBeenCalledWith(9);
    expect(wrapper.text()).toContain('ANA SILVA');
    expect(wrapper.text()).toContain('Ana Silva');
    expect(wrapper.find('.line-through').text()).toContain('ANA SILVA');
    expect(wrapper.text()).toContain(
      '"motivo":"AUTONOMIA_GUIDE.TASK.SKIP.nao_encontrado"'
    );
    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.TASK.TIME:{"minutos":10}'
    );
  });

  it('diz o que fazer quando não carrega, e tenta de novo', async () => {
    AutonomiaGuideAPI.tarefa.mockRejectedValueOnce(new Error('rede'));
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain(
      'AUTONOMIA_GUIDE.TASK.LOAD_FAILED'
    );

    AutonomiaGuideAPI.tarefa.mockResolvedValue({ data: tarefa() });
    await botao(wrapper, 'AUTONOMIA_GUIDE.TASK.RETRY').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.TASK.START');
  });

  it('avisa quando não há exemplo na amostra', () => {
    const wrapper = montar({ inicial: tarefa({ amostra: [] }) });

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.TASK.SAMPLE_EMPTY');
  });

  it('Começar chama o servidor e passa a mostrar o andamento', async () => {
    AutonomiaGuideAPI.comandarTarefa.mockResolvedValue({
      data: tarefa({ status: 'na_fila' }),
    });
    AutonomiaGuideAPI.tarefa.mockResolvedValue({
      data: tarefa({ status: 'rodando', feitos: 120 }),
    });
    const wrapper = montar({ inicial: tarefa() });

    await botao(wrapper, 'AUTONOMIA_GUIDE.TASK.START').trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.comandarTarefa).toHaveBeenCalledWith(9, 'comecar');
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.TASK.QUEUED');
    wrapper.unmount();
  });

  it('na pausa de segurança mostra o que mudou e Seguir', async () => {
    AutonomiaGuideAPI.comandarTarefa.mockResolvedValue({
      data: tarefa({ status: 'na_fila' }),
    });
    const wrapper = montar({
      inicial: tarefa({
        status: 'aguardando_ok_canario',
        feitos: 25,
        canario: {
          tabelas: { contacts: 25 },
          jobs: { EventDispatcherJob: 25, WebhookJob: 1 },
          itens: 25,
        },
      }),
    });

    expect(wrapper.find('[data-banner]').text()).toContain('{"n":25}');
    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.TASK.CHECK_TABLE:{"n":25,"nome":"AUTONOMIA_GUIDE.TASK.TABLES.contacts"}'
    );
    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.TASK.CHECK_JOBS:{"n":26}'
    );

    await botao(wrapper, 'AUTONOMIA_GUIDE.TASK.CONTINUE').trigger('click');
    await flushPromises();
    expect(AutonomiaGuideAPI.comandarTarefa).toHaveBeenCalledWith(9, 'seguir');
    wrapper.unmount();
  });

  // Sobrevive a fechar e reabrir: o cartão busca de novo pelo id e continua de onde está.
  it('mostra "120 de 512" ao reabrir, com Pausar, e acompanha o andamento', async () => {
    vi.useFakeTimers();
    AutonomiaGuideAPI.tarefa
      .mockResolvedValueOnce({
        data: tarefa({ status: 'rodando', feitos: 120 }),
      })
      .mockResolvedValue({ data: tarefa({ status: 'rodando', feitos: 145 }) });
    const wrapper = montar();
    await flushPromises();

    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.TASK.PROGRESS:{"feitos":120,"total":512}'
    );
    expect(
      wrapper.find('[role="progressbar"]').attributes('aria-valuenow')
    ).toBe('23');

    await vi.advanceTimersByTimeAsync(3000);
    expect(wrapper.text()).toContain('{"feitos":145,"total":512}');

    AutonomiaGuideAPI.comandarTarefa.mockResolvedValue({
      data: tarefa({ status: 'pausada', feitos: 145, motivo: 'Você pausou.' }),
    });
    await botao(wrapper, 'AUTONOMIA_GUIDE.TASK.PAUSE').trigger('click');
    await flushPromises();
    expect(AutonomiaGuideAPI.comandarTarefa).toHaveBeenCalledWith(9, 'pausar');
    expect(wrapper.text()).toContain('Você pausou.');
    wrapper.unmount();
    vi.useRealTimers();
  });

  it('no relatório agrupa o que não foi feito e oferece Desfazer tudo com prazo', async () => {
    AutonomiaGuideAPI.comandarTarefa.mockResolvedValue({
      data: tarefa({ status: 'desfazendo', lotes: 3 }),
    });
    AutonomiaGuideAPI.tarefa.mockResolvedValue({
      data: tarefa({ status: 'desfazendo', lotes: 3 }),
    });
    const wrapper = montar({
      inicial: tarefa({
        status: 'concluida',
        feitos: 500,
        lotes: 21,
        nao_feitos: [{ status: 'pulado', motivo: 'nao_encontrado', total: 12 }],
        desfazivel: true,
        desfazer_ate: '2026-10-09T18:00:00Z',
      }),
    });

    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.TASK.DONE_COUNT:{"n":500,"total":512}'
    );
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.TASK.NOT_DONE.pulado');
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.DONE.UNTIL');

    await botao(wrapper, 'AUTONOMIA_GUIDE.TASK.UNDO_ALL').trigger('click');
    await flushPromises();
    expect(AutonomiaGuideAPI.comandarTarefa).toHaveBeenCalledWith(
      9,
      'desfazer'
    );
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.TASK.UNDOING');
    wrapper.unmount();
  });

  it('mostra o motivo do servidor quando o comando é recusado', async () => {
    AutonomiaGuideAPI.comandarTarefa.mockRejectedValue({
      response: { data: { error: 'Esta tarefa não pode fazer isso agora.' } },
    });
    const wrapper = montar({ inicial: tarefa() });

    await botao(wrapper, 'AUTONOMIA_GUIDE.TASK.START').trigger('click');
    await flushPromises();

    expect(wrapper.find('[role="alert"]').text()).toContain(
      'Esta tarefa não pode fazer isso agora.'
    );
  });

  it('tem os textos em inglês e em português', () => {
    const chaves = objeto =>
      Object.entries(objeto).flatMap(([chave, valor]) =>
        typeof valor === 'object'
          ? chaves(valor).map(sub => `${chave}.${sub}`)
          : [chave]
      );

    expect(chaves(ptBR.AUTONOMIA_GUIDE.TASK).sort()).toEqual(
      chaves(en.AUTONOMIA_GUIDE.TASK).sort()
    );
  });
});
