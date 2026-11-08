import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import BaseDoAgenteLinha from '../../components/pagina/BaseDoAgenteLinha.vue';
import GavetaNovaBase from '../../components/pagina/GavetaNovaBase.vue';
import { useBaseDoAgente } from '../../composables/useBaseDoAgente';
import { rotuloDoTipo } from '../../utils/baseDoAgente';

// #1429 F3 — a linha "Base de seguros" e a gaveta do antes e depois, com a cópia real em pt_BR e o formato da API.
withFullI18n('pt_BR');

const api = vi.hoisted(() => ({
  ler: vi.fn(),
  comparar: vi.fn(),
  atualizar: vi.fn(),
  desfazer: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/baseDoAgente', () => ({ default: api }));
// A gaveta teleporta com a direção do texto, lida do store.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ getters: {}, dispatch: vi.fn() }),
    useMapGetter: () => computed(() => false),
  };
});

const corretora = { segmento: 'seguros/corretora', data: '2026-10-21' };
const seguradora = { segmento: 'seguros/seguradora', data: '2026-10-02' };
const novaCorretora = { ...corretora, versao: 'bc7dee3b0b25' };

const base = (extra = {}) => ({
  situacao: 'sem_base',
  atual: null,
  nova: novaCorretora,
  pode_atualizar: true,
  desfazer: null,
  ...extra,
});

const linha = (props = {}) =>
  mount(BaseDoAgenteLinha, {
    props: { base: base(), nome: 'Bia', podeGerenciar: true, ...props },
  });

describe('rotuloDoTipo', () => {
  it('names each insurance type by i18n, never by the raw segment', () => {
    const t = chave => chave;
    expect(rotuloDoTipo('seguros/saude_beneficios', t)).toBe(
      'AGENTS.JORNADA.PAGINA.BASE.TIPOS.SAUDE_BENEFICIOS'
    );
    expect(rotuloDoTipo(null, t)).toBe('');
    expect(rotuloDoTipo('seguros/novo_tipo', t)).toBe(
      'AGENTS.JORNADA.PAGINA.BASE.TIPOS.OUTRO'
    );
  });
});

describe('BaseDoAgenteLinha', () => {
  it('without a base: says so, explains, and offers the new one to who manages', async () => {
    const wrapper = linha();

    expect(wrapper.find('[data-base-atual]').text()).toBe(
      'Bia ainda trabalha sem base de seguros.'
    );
    expect(wrapper.text()).toContain(
      'É o que Bia sabe sobre o ramo de seguros. Só muda quando alguém atualiza.'
    );
    expect(wrapper.find('[data-base-nova]').text()).toBe(
      'Base nova disponível: Corretora · de 21/10/2026'
    );
    await wrapper.find('[data-base-atualizar]').trigger('click');
    expect(wrapper.emitted('atualizar')).toHaveLength(1);
  });

  it('with a base: shows the type and the date', () => {
    const wrapper = linha({
      base: base({ situacao: 'em_dia', atual: corretora, nova: null }),
    });

    expect(wrapper.find('[data-base-atual]').text()).toBe(
      'Corretora · de 21/10/2026'
    );
    expect(wrapper.find('[data-base-atualizar]').exists()).toBe(false);
  });

  it('a base with no known date shows only the type', () => {
    const wrapper = linha({
      base: base({
        situacao: 'antiga',
        atual: { segmento: 'seguros/corretora', data: null },
      }),
    });

    expect(wrapper.find('[data-base-atual]').text()).toBe('Corretora');
  });

  it('when the account changed type, says it', () => {
    const wrapper = linha({
      base: base({ situacao: 'conta_mudou', atual: seguradora }),
    });

    expect(wrapper.find('[data-base-nova]').text()).toBe(
      'A conta agora é Corretora. Base nova disponível: Corretora · de 21/10/2026'
    );
  });

  it('who only views reads the line, with no notice and no button', () => {
    const wrapper = linha({ podeGerenciar: false });

    expect(wrapper.find('[data-base-atual]').exists()).toBe(true);
    expect(wrapper.find('[data-base-nova]').exists()).toBe(false);
    expect(wrapper.find('[data-base-atualizar]').exists()).toBe(false);
  });

  it('without pode_atualizar there is no notice nor button', () => {
    const wrapper = linha({
      base: base({
        situacao: 'conta_mudou',
        atual: seguradora,
        nova: null,
        pode_atualizar: false,
      }),
    });

    expect(wrapper.find('[data-base-nova]').exists()).toBe(false);
    expect(wrapper.find('[data-base-atualizar]').exists()).toBe(false);
  });

  it('right after updating, offers Undo', async () => {
    const wrapper = linha({
      base: base({
        situacao: 'em_dia',
        atual: corretora,
        nova: null,
        pode_atualizar: false,
        desfazer: { anterior: null },
      }),
    });

    expect(wrapper.find('[data-base-atualizada]').exists()).toBe(true);
    await wrapper.find('[data-base-desfazer]').trigger('click');
    expect(wrapper.emitted('desfazer')).toHaveLength(1);
  });

  it('after a refused undo, says nothing changed even without the button', () => {
    const wrapper = linha({
      base: base({ situacao: 'em_dia', atual: corretora, nova: null }),
      erroDesfazer: true,
    });

    expect(wrapper.find('[data-base-desfazer]').exists()).toBe(false);
    expect(wrapper.find('[data-base-erro-desfazer]').text()).toBe(
      'Não deu para desfazer agora. Nada mudou.'
    );
  });

  it('when undo no longer applies (409), shows the server reason, with no retry', () => {
    const wrapper = linha({
      base: base({ situacao: 'em_dia', atual: corretora, nova: null }),
      erroDesfazer: true,
      textoErroDesfazer:
        'O agente mudou depois da atualização, e o Desfazer não vale mais. Para voltar, use o histórico de versões.',
    });

    expect(wrapper.find('[data-base-erro-desfazer]').text()).toBe(
      'O agente mudou depois da atualização, e o Desfazer não vale mais. Para voltar, use o histórico de versões.'
    );
    expect(wrapper.find('[data-base-desfazer]').exists()).toBe(false);
  });

  it('has no native select', () => {
    expect(linha().find('select').exists()).toBe(false);
  });
});

describe('GavetaNovaBase', () => {
  const perguntas = [
    {
      pergunta: 'O que é franquia?',
      hoje: 'É um valor.',
      hoje_equipe: false,
      nova: 'É a parte do conserto que fica com você.',
      nova_equipe: false,
    },
    {
      pergunta: 'Vocês mesmos aprovam o meu sinistro?',
      hoje: null,
      hoje_equipe: true,
      nova: 'Quem aprova é a seguradora.',
      nova_equipe: false,
    },
  ];

  const gaveta = (props = {}) =>
    mount(GavetaNovaBase, {
      attachTo: document.body,
      props: {
        base: base({ situacao: 'conta_mudou', atual: seguradora }),
        nome: 'Bia',
        comparar: vi
          .fn()
          .mockResolvedValue({ versao: 'bc7dee3b0b25', perguntas }),
        atualizar: vi.fn().mockResolvedValue(),
        ...props,
      },
    });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('shows the confirm button only after the answers arrive', async () => {
    let responder;
    const comparar = vi.fn(
      () =>
        new Promise(resolve => {
          responder = resolve;
        })
    );
    const wrapper = gaveta({ comparar });
    await flushPromises();

    expect(document.querySelector('[data-comparando]')).not.toBeNull();
    expect(document.querySelector('[data-confirmar-base]')).toBeNull();

    responder({ versao: 'bc7dee3b0b25', perguntas });
    await flushPromises();

    expect(document.querySelectorAll('[data-pergunta-comparada]')).toHaveLength(
      2
    );
    expect(document.querySelector('[data-confirmar-base]')).not.toBeNull();
    wrapper.unmount();
  });

  it('labels today and the new base, and says when the agent would hand over to the team', async () => {
    const wrapper = gaveta();
    await flushPromises();

    const hoje = [...document.querySelectorAll('[data-resposta="hoje"]')];
    expect(hoje[0].textContent).toContain('Hoje (Seguradora · de 02/10/2026)');
    expect(hoje[1].textContent).toContain('Passaria a conversa para a equipe.');
    expect(
      document.querySelector('[data-resposta="nova"]').textContent
    ).toContain('Com a base nova (Corretora · de 21/10/2026)');
    wrapper.unmount();
  });

  it('confirms and tells the page it was updated', async () => {
    const atualizar = vi.fn().mockResolvedValue();
    const wrapper = gaveta({ atualizar });
    await flushPromises();

    document.querySelector('[data-confirmar-base]').click();
    await flushPromises();

    expect(atualizar).toHaveBeenCalledWith('bc7dee3b0b25');
    expect(wrapper.emitted('atualizado')).toHaveLength(1);
    wrapper.unmount();
  });

  it('a failed update says nothing changed and keeps the drawer', async () => {
    const wrapper = gaveta({
      atualizar: vi.fn().mockRejectedValue(new Error('rede')),
    });
    await flushPromises();

    document.querySelector('[data-confirmar-base]').click();
    await flushPromises();

    expect(
      document.querySelector('[data-erro-atualizar]').textContent
    ).toContain('Não deu para atualizar agora. Nada mudou.');
    expect(wrapper.emitted('atualizado')).toBeUndefined();
    wrapper.unmount();
  });

  it('when the new base changed meanwhile (409), never saves it: back to the error with Try again', async () => {
    const erro = Object.assign(new Error('409'), {
      response: {
        status: 409,
        data: { error: 'O agente mudou enquanto isso.' },
      },
    });
    const comparar = vi
      .fn()
      .mockResolvedValue({ versao: 'bc7dee3b0b25', perguntas });
    const atualizar = vi.fn().mockRejectedValue(erro);
    const wrapper = gaveta({ comparar, atualizar });
    await flushPromises();

    document.querySelector('[data-confirmar-base]').click();
    await flushPromises();

    expect(
      document.querySelector('[data-erro-comparar]').textContent
    ).toContain('O agente mudou enquanto isso.');
    expect(document.querySelector('[data-confirmar-base]')).toBeNull();
    expect(atualizar).toHaveBeenCalledTimes(1);
    wrapper.unmount();
  });

  it('announces when the answers arrive', async () => {
    const wrapper = gaveta();
    await flushPromises();

    expect(
      document.querySelector('[data-respostas-prontas]').getAttribute('role')
    ).toBe('status');
    wrapper.unmount();
  });

  it('closing the drawer stops waiting for the comparison', async () => {
    let sinal;
    const comparar = vi.fn(signal => {
      sinal = signal;
      return new Promise(() => {});
    });
    const wrapper = gaveta({ comparar });
    await flushPromises();

    wrapper.unmount();

    expect(sinal.aborted).toBe(true);
  });

  it('over the limit, shows only the wait: server message, no Try again, no confirm button', async () => {
    const erro = Object.assign(new Error('429'), {
      response: {
        status: 429,
        data: { error: 'Espere uns 2 minutos para comparar de novo.' },
      },
    });
    const wrapper = gaveta({ comparar: vi.fn().mockRejectedValue(erro) });
    await flushPromises();

    const aviso = document.querySelector('[data-erro-comparar]');
    expect(aviso.textContent).toContain(
      'Espere uns 2 minutos para comparar de novo.'
    );
    expect(aviso.textContent).not.toContain('Tentar de novo');
    expect(aviso.querySelector('button')).toBeNull();
    expect(document.querySelector('[data-confirmar-base]')).toBeNull();
    wrapper.unmount();
  });

  it.each(['sem_base_nova', 'sem_instrucao'])(
    'a permanent refusal (422 %s) shows the reason with no Try again',
    async code => {
      const erro = Object.assign(new Error('422'), {
        response: { status: 422, data: { error: 'Motivo do servidor.', code } },
      });
      const wrapper = gaveta({ comparar: vi.fn().mockRejectedValue(erro) });
      await flushPromises();

      const aviso = document.querySelector('[data-erro-comparar]');
      expect(aviso.textContent).toContain('Motivo do servidor.');
      expect(aviso.querySelector('button')).toBeNull();
      wrapper.unmount();
    }
  );

  it('when the comparison itself fails (no code), offers Try again', async () => {
    const wrapper = gaveta({
      comparar: vi.fn().mockRejectedValue(new Error('ai_request_failed')),
    });
    await flushPromises();

    expect(
      document.querySelector('[data-erro-comparar]').textContent
    ).toContain('Tentar de novo');
    wrapper.unmount();
  });

  it('when the server asks to compare first (422), goes back to the error with Try again', async () => {
    const erro = Object.assign(new Error('422'), {
      response: {
        status: 422,
        data: {
          error: 'Compare as respostas antes de atualizar a base.',
          code: 'comparar_antes',
        },
      },
    });
    const wrapper = gaveta({ atualizar: vi.fn().mockRejectedValue(erro) });
    await flushPromises();

    document.querySelector('[data-confirmar-base]').click();
    await flushPromises();

    const aviso = document.querySelector('[data-erro-comparar]');
    expect(aviso.textContent).toContain(
      'Compare as respostas antes de atualizar a base.'
    );
    expect(aviso.textContent).toContain('Tentar de novo');
    expect(document.querySelector('[data-erro-atualizar]')).toBeNull();
    wrapper.unmount();
  });
});

describe('useBaseDoAgente', () => {
  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
  });

  it('hides the line when the API says there is nothing to show or fails', async () => {
    api.ler.mockResolvedValueOnce({ data: { situacao: null } });
    const base1 = useBaseDoAgente(7);
    await base1.carregar();
    expect(base1.temOQueMostrar.value).toBe(false);

    api.ler.mockRejectedValueOnce(new Error('404'));
    const base2 = useBaseDoAgente(7);
    await base2.carregar();
    expect(base2.temOQueMostrar.value).toBe(false);
  });

  it('updates with the version that was compared', async () => {
    api.ler.mockResolvedValue({ data: base() });
    api.atualizar.mockResolvedValue({ data: base({ situacao: 'em_dia' }) });
    const estado = useBaseDoAgente(7);
    await estado.carregar();

    await estado.atualizar('bc7dee3b0b25');

    expect(api.atualizar).toHaveBeenCalledWith(7, 'bc7dee3b0b25');
    expect(estado.base.value.situacao).toBe('em_dia');
  });

  it('a refused undo reads the line again and keeps the error', async () => {
    api.ler.mockResolvedValue({ data: base({ desfazer: { anterior: null } }) });
    api.desfazer.mockRejectedValue(new Error('409'));
    const estado = useBaseDoAgente(7);
    await estado.carregar();
    api.ler.mockResolvedValue({ data: base({ desfazer: null }) });

    expect(await estado.desfazer()).toBe(false);
    await flushPromises();

    expect(estado.erroDesfazer.value).toBe(true);
    expect(estado.textoErroDesfazer.value).toBe('');
    expect(estado.base.value.desfazer).toBeNull();
  });

  it('keeps the server reason when undo no longer applies (409)', async () => {
    api.ler.mockResolvedValue({ data: base({ desfazer: { anterior: null } }) });
    api.desfazer.mockRejectedValue(
      Object.assign(new Error('409'), {
        response: { status: 409, data: { error: 'Use o histórico.' } },
      })
    );
    const estado = useBaseDoAgente(7);
    await estado.carregar();

    await estado.desfazer();

    expect(estado.erroDesfazer.value).toBe(true);
    expect(estado.textoErroDesfazer.value).toBe('Use o histórico.');
  });

  it('reads the line again when the update fails, and passes the error on', async () => {
    api.ler.mockResolvedValue({ data: base() });
    api.atualizar.mockRejectedValue(new Error('409'));
    const estado = useBaseDoAgente(7);
    await estado.carregar();

    await expect(estado.atualizar()).rejects.toThrow('409');
    expect(api.ler).toHaveBeenCalledTimes(2);
  });
});
