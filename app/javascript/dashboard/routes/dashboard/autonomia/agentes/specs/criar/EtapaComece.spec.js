import { mount } from '@vue/test-utils';
import EtapaComece from '../../components/criar/EtapaComece.vue';

const permissoes = vi.hoisted(() => ({ conectar: true }));
vi.mock('../../composables/usePermissoesDaJornada', async () => {
  const { computed } = await import('vue');
  return {
    usePermissoesDaJornada: () => ({
      podeConectarCanal: computed(() => permissoes.conectar),
      podeEscolherQuemRecebe: computed(() => true),
    }),
  };
});
// A gaveta vai para o body pelo TeleportWithDirection, que lê a direção do texto na store.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});
vi.mock('vue-router', () => ({
  useRouter: () => ({ resolve: rota => ({ href: `/app/${rota.name}` }) }),
}));

const livre = { inbox_id: 10, name: 'WhatsApp da Loja', occupied_by: null };
const ocupado = {
  inbox_id: 11,
  name: 'WhatsApp do Centro',
  occupied_by: { kind: 'agent', agent_id: 9, agent_name: 'Bia' },
};
const externo = {
  inbox_id: 12,
  name: 'Instagram',
  occupied_by: { kind: 'external' },
};

const montar = props =>
  mount(EtapaComece, {
    props: {
      nome: 'Duda',
      agenteId: 5,
      canais: [livre, ocupado, externo],
      ondeInicial: 10,
      ...props,
    },
    attachTo: document.body,
  });

const corpo = () => document.body;
const botaoComecar = () => corpo().querySelector('[data-comecar]');
const radios = () => [...corpo().querySelectorAll('[role="radio"]')];

describe('EtapaComece', () => {
  afterEach(() => {
    document.body.innerHTML = '';
    permissoes.conectar = true;
  });

  it('is a drawer named after the agent, with focus trapped inside', () => {
    const wrapper = montar();
    const gaveta = corpo().querySelector('[role="dialog"]');
    expect(gaveta.getAttribute('aria-modal')).toBe('true');
    expect(gaveta.textContent).toContain('AGENTS.JORNADA.ONDE_QUANDO.TITULO');
    expect(gaveta.contains(document.activeElement)).toBe(true);
    wrapper.unmount();
  });

  it('starts with the suggested inbox and "Always", and starts answering there', async () => {
    const wrapper = montar();
    expect(radios()[0].getAttribute('aria-checked')).toBe('true');
    expect(botaoComecar().textContent).toContain(
      'AGENTS.JORNADA.CRIAR.COMECE.COMECAR'
    );
    botaoComecar().click();
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('comecar')[0][0]).toEqual({
      inboxId: 10,
      quando: 'always',
      troca: null,
    });
    wrapper.unmount();
  });

  it('choosing a busy inbox explains the swap and renames the button', async () => {
    const wrapper = montar();
    radios()[1].click();
    await wrapper.vm.$nextTick();
    expect(corpo().querySelector('[data-troca]')).not.toBeNull();
    expect(botaoComecar().textContent).toContain(
      'AGENTS.JORNADA.CRIAR.COMECE.TROCAR'
    );
    botaoComecar().click();
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('comecar')[0][0].troca).toEqual({
      agenteId: 9,
      nome: 'Bia',
      canal: 'WhatsApp do Centro',
    });
    wrapper.unmount();
  });

  it('never starts on an inbox that belongs to another system', async () => {
    const wrapper = montar({ ondeInicial: 12 });
    expect(botaoComecar().disabled).toBe(true);
    radios()[2].click();
    await wrapper.vm.$nextTick();
    expect(radios()[2].getAttribute('aria-checked')).toBe('false');
    wrapper.unmount();
  });

  it('when every inbox is taken, says so and offers to connect another one', async () => {
    const wrapper = montar({ canais: [ocupado, externo], ondeInicial: 11 });
    const link = corpo().querySelector('[data-todos-ocupados] a');
    expect(link.getAttribute('href')).toBe('/app/settings_inbox_new');
    wrapper.unmount();

    permissoes.conectar = false;
    const semPermissao = montar({ canais: [ocupado], ondeInicial: 11 });
    expect(corpo().querySelector('[data-todos-ocupados] a')).toBeNull();
    expect(
      corpo().querySelector('[data-todos-ocupados]').textContent
    ).toContain('AGENTS.JORNADA.HEROI.SEM_CANAL_SEM_PERMISSAO');
    semPermissao.unmount();
  });

  it.each([
    ['comecar', 'AGENTS.JORNADA.ERRO.COMECAR_ATENDER_GARANTIA'],
    ['canal', 'AGENTS.JORNADA.ERRO.CANAL_GARANTIA'],
    ['offline', 'AGENTS.JORNADA.ERRO.OFFLINE'],
    ['troca_sem_agente', 'AGENTS.JORNADA.ERRO.TROCA_SEM_AGENTE_GARANTIA'],
  ])(
    'shows the %s failure in the drawer, saying what did not change',
    (motivo, texto) => {
      const wrapper = montar({
        erro: { motivo, troca: { canal: 'WhatsApp do Centro' } },
      });
      expect(
        corpo().querySelector('[data-erro-comecar]').textContent
      ).toContain(texto);
      wrapper.unmount();
    }
  );

  it('"Choose another" (channel refused) takes the focus to the list', async () => {
    const wrapper = montar({ erro: { motivo: 'canal' } });
    corpo().querySelector('[data-erro-comecar] button').click();
    await wrapper.vm.$nextTick();
    expect(document.activeElement.getAttribute('role')).toBe('radio');
    expect(wrapper.emitted('comecar')).toBeUndefined();
    wrapper.unmount();
  });

  it('"Try again" on a start failure tries the same choice again', async () => {
    const wrapper = montar({ erro: { motivo: 'comecar' } });
    corpo().querySelector('[data-erro-comecar] button').click();
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('comecar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('keeps the button focusable while starting, and blocks a second click', async () => {
    const wrapper = montar({ comecando: true });
    expect(botaoComecar().getAttribute('aria-disabled')).toBe('true');
    botaoComecar().click();
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('comecar')).toBeUndefined();
    wrapper.unmount();
  });

  it('"Back to the test" closes the drawer', async () => {
    const wrapper = montar();
    corpo().querySelector('[data-voltar-teste]').click();
    await wrapper.vm.$nextTick();
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('never renders a native select', () => {
    const wrapper = montar();
    expect(corpo().querySelector('select')).toBeNull();
    wrapper.unmount();
  });
});
