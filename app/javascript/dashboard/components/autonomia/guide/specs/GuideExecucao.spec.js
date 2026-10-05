import { ref } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AutonomiaGuideAPI from 'dashboard/api/autonomiaGuide';
import GuideExecucao from '../GuideExecucao.vue';

vi.mock('vue-i18n', () => ({
  // O valor real que o Chatwoot guarda, com sublinhado (o Intl não aceita).
  useI18n: () => ({ t: key => key, locale: ref('pt_BR') }),
}));
vi.mock('dashboard/api/autonomiaGuide', () => ({
  default: { desfazer: vi.fn() },
}));

// #855 — o Guia age sem confirmação; o cartão é onde a pessoa vê o que mudou e
// volta atrás.
const execucao = (extra = {}) => ({
  id: 7,
  passos: [
    { frase: 'Criei a função Marketing.', ok: true },
    { frase: 'Apliquei a função à Ana.', ok: false },
  ],
  pendencias: [],
  desfazivel: true,
  desfeita_em: null,
  expira_em: '2026-10-07T18:00:00Z',
  criada_em: '2026-10-02T18:00:00Z',
  relatorio: null,
  ...extra,
});

const montar = props =>
  mount(GuideExecucao, {
    props: { execucao: execucao(), ...props },
    global: {
      mocks: {
        $t: (key, valores) =>
          valores ? `${key}:${JSON.stringify(valores)}` : key,
      },
      stubs: {
        Button: {
          props: ['label', 'disabled'],
          emits: ['click'],
          template:
            '<button :disabled="disabled" @click="$emit(\'click\')">{{ label }}</button>',
        },
      },
    },
  });

describe('GuideExecucao', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lista cada passo, dizendo o que deu certo e o que não deu', () => {
    const texto = montar().text();

    expect(texto).toContain('Criei a função Marketing.');
    expect(texto).toContain('Apliquei a função à Ana.');
    expect(texto).toContain('AUTONOMIA_GUIDE.DONE.STEP_FAILED');
  });

  it('desfaz e mostra que voltou ao que era', async () => {
    AutonomiaGuideAPI.desfazer.mockResolvedValue({
      data: {
        execucao: execucao({
          desfazivel: false,
          desfeita_em: '2026-10-02T18:05:00Z',
          relatorio: { desfeitas: 2, conflitos: [] },
        }),
      },
    });
    const wrapper = montar();

    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(AutonomiaGuideAPI.desfazer).toHaveBeenCalledWith(7);
    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.DONE.UNDONE');
    expect(wrapper.find('button').exists()).toBe(false);
  });

  // Desfazer não apaga trabalho de outra pessoa — e a tela tem que dizer.
  it('avisa o que ficou porque alguém mexeu depois', () => {
    const wrapper = montar({
      execucao: execucao({
        desfazivel: false,
        desfeita_em: '2026-10-02T18:05:00Z',
        relatorio: { desfeitas: 1, conflitos: [{ motivo: 'changed_after' }] },
      }),
    });

    expect(wrapper.text()).toContain(
      'AUTONOMIA_GUIDE.DONE.CONFLICTS:{"count":1}'
    );
  });

  it('avisa quando parte não tem volta', () => {
    const wrapper = montar({ execucao: execucao({ pendencias: ['labels'] }) });

    expect(wrapper.text()).toContain('AUTONOMIA_GUIDE.DONE.PARTIAL');
  });

  it('mostra o motivo da plataforma quando o desfazer é recusado', async () => {
    AutonomiaGuideAPI.desfazer.mockRejectedValue({
      response: { data: { error: 'Isto já foi desfeito.' } },
    });
    const wrapper = montar();

    await wrapper.find('button').trigger('click');
    await flushPromises();

    expect(wrapper.text()).toContain('Isto já foi desfeito.');
  });
});
