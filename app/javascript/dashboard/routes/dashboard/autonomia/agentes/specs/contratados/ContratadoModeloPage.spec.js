import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import ContratadoModeloPage from '../../pages/ContratadoModeloPage.vue';

// #3211 (Tarefa 27) — a página do agente pronto e o passo 1 (os dados da corretora). O servidor recusa com
// 422 { error, code, campo } (R14): o campo destacado é o `campo` da resposta; `campo` nulo vai para o topo.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});
const router = vi.hoisted(() => ({ push: vi.fn() }));
vi.mock('vue-router', () => ({ useRouter: () => router }));
const papel = vi.hoisted(() => ({ admin: true }));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => papel.admin) }) };
});
const api = vi.hoisted(() => ({ contratar: vi.fn(), lista: vi.fn() }));
vi.mock('dashboard/api/autonomia/contratados', () => ({ default: api }));

const UNIVERSAL = 'seguro_viagem_universal';

const no = seletor => document.querySelector(seletor);
const campo = nome => no(`[data-campo="${nome}"]`);
const digitar = async (nome, valor) => {
  const elemento = campo(nome);
  elemento.value = valor;
  elemento.dispatchEvent(new Event('input'));
  await nextTick();
};
const invalido = nome => campo(nome).getAttribute('aria-invalid') === 'true';

const recusa = dados =>
  Object.assign(new Error('422'), {
    response: { status: 422, data: dados },
  });

const montar = async (modelo = UNIVERSAL) => {
  const wrapper = mount(ContratadoModeloPage, {
    attachTo: document.body,
    props: { modelo },
  });
  await flushPromises();
  return wrapper;
};

const abrirFormulario = async wrapper => {
  await wrapper.get('[data-contratar]').trigger('click');
  await flushPromises();
};

const enviar = async () => {
  no('[data-contratar-enviar]').click();
  await flushPromises();
};

const preencher = async () => {
  await digitar('nome_agente', 'Bia');
  await digitar('nome_corretora', 'Corretora Exemplo');
  await digitar('sobre_corretora', 'Corretora em Campinas desde 2010.');
};

describe('ContratadoModeloPage (#3211)', () => {
  beforeEach(() => {
    papel.admin = true;
    router.push.mockClear();
    api.contratar.mockResolvedValue({ data: { id: 42 } });
    api.lista.mockResolvedValue({
      data: { modelos: [UNIVERSAL], falta_chave_de_ia: false },
    });
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('says what the agent does and what it will ask for, before hiring', async () => {
    const wrapper = await montar();
    const texto = wrapper.text();

    expect(wrapper.get('h1').text()).toBe('AGENTS.CONTRATADOS.MODELO.TITULO');
    [
      'MODELO.FAZ.DUVIDAS',
      'MODELO.FAZ.COTA',
      'MODELO.FAZ.ESCOLHE',
      'MODELO.FAZ.PROPOSTA',
      'MODELO.PRECISA.DADOS',
      'MODELO.PRECISA.LOGIN',
      'MODELO.PRECISA.CANAL',
      'MODELO.PRONTO',
    ].forEach(chave => expect(texto).toContain(`AGENTS.CONTRATADOS.${chave}`));
    expect(no('[data-campo]')).toBeNull();
    wrapper.unmount();
  });

  it('opens the three fields with the server limits and the counter on the description', async () => {
    const wrapper = await montar();
    await abrirFormulario(wrapper);

    expect(document.body.textContent).toContain(
      'AGENTS.CONTRATADOS.CONTRATAR.PASSO'
    );
    expect(campo('nome_agente').getAttribute('maxlength')).toBe('120');
    expect(campo('nome_corretora').getAttribute('maxlength')).toBe('120');
    expect(campo('sobre_corretora').getAttribute('maxlength')).toBe('1000');
    expect(no('[data-contador]').textContent).toContain(
      'AGENTS.CONTRATADOS.CONTRATAR.SOBRE.CONTADOR'
    );
    wrapper.unmount();
  });

  it('does not send while the required fields are empty', async () => {
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await digitar('sobre_corretora', 'Só a apresentação.');
    await enviar();

    expect(api.contratar).not.toHaveBeenCalled();
    expect(invalido('nome_agente')).toBe(true);
    expect(invalido('nome_corretora')).toBe(true);
    expect(invalido('sobre_corretora')).toBe(false);
    const texto = document.body.textContent;
    expect(texto).toContain('AGENTS.CONTRATADOS.CONTRATAR.NOME.ERRO');
    expect(texto).toContain('AGENTS.CONTRATADOS.CONTRATAR.CORRETORA.ERRO');
    wrapper.unmount();
  });

  it('sends exactly the three fields, without spaces at the ends', async () => {
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await digitar('nome_agente', '  Bia ');
    await digitar('nome_corretora', 'Corretora Exemplo ');
    await digitar('sobre_corretora', ' Corretora em Campinas desde 2010.');
    await enviar();

    expect(api.contratar).toHaveBeenCalledTimes(1);
    expect(api.contratar).toHaveBeenCalledWith(UNIVERSAL, {
      nomeAgente: 'Bia',
      nomeCorretora: 'Corretora Exemplo',
      sobreCorretora: 'Corretora em Campinas desde 2010.',
    });
    wrapper.unmount();
  });

  it('goes to the new agent with the hired-agent drawer open', async () => {
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await preencher();
    await enviar();

    expect(router.push).toHaveBeenCalledWith({
      name: 'autonomia_agent_panel',
      params: { agentId: 42 },
      query: { gaveta: 'contratado' },
    });
    wrapper.unmount();
  });

  it('marks only the field the server named in the 422', async () => {
    api.contratar.mockRejectedValue(
      recusa({
        error: 'texto do servidor',
        code: 'marcador',
        campo: 'nome_corretora',
      })
    );
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await preencher();
    await enviar();

    expect(invalido('nome_corretora')).toBe(true);
    expect(invalido('nome_agente')).toBe(false);
    expect(invalido('sobre_corretora')).toBe(false);
    const descricao = campo('nome_corretora').getAttribute('aria-describedby');
    const erroId = descricao.split(' ')[0];
    expect(document.getElementById(erroId).textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.MARCADOR'
    );
    expect(no('[data-erro-do-formulario]')).toBeNull();
    expect(router.push).not.toHaveBeenCalled();
    wrapper.unmount();
  });

  it('shows "unavailable" at the top of the form, without marking a field', async () => {
    api.contratar.mockRejectedValue(
      recusa({ error: 'texto do servidor', code: 'indisponivel', campo: null })
    );
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await preencher();
    await enviar();

    expect(invalido('nome_agente')).toBe(false);
    expect(invalido('nome_corretora')).toBe(false);
    expect(invalido('sobre_corretora')).toBe(false);
    expect(no('[data-erro-do-formulario]').textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.INDISPONIVEL'
    );
    wrapper.unmount();
  });

  it('says what is missing when the account has no AI key of its own', async () => {
    api.contratar.mockRejectedValue(
      recusa({
        error: 'texto do servidor',
        code: 'sem_chave_de_ia',
        campo: null,
      })
    );
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await preencher();
    await enviar();

    expect(invalido('nome_agente')).toBe(false);
    expect(no('[data-erro-do-formulario]').textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.SEM_CHAVE_DE_IA'
    );
    wrapper.unmount();
  });

  describe('account without its own AI key', () => {
    beforeEach(() => {
      api.lista.mockResolvedValue({
        data: { modelos: [UNIVERSAL], falta_chave_de_ia: true },
      });
    });

    it('warns before "Contratar", which stays off, and takes the admin to Integrations', async () => {
      const wrapper = await montar();

      const aviso = no('[data-falta-chave-de-ia]');
      expect(aviso.textContent).toContain(
        'AGENTS.CONTRATADOS.MODELO.SEM_CHAVE_DE_IA.TITULO'
      );
      expect(aviso.textContent).toContain(
        'AGENTS.CONTRATADOS.MODELO.SEM_CHAVE_DE_IA.TEXTO'
      );
      expect(no('[data-contratar]').disabled).toBe(true);
      expect(no('[data-contratar-celular]').disabled).toBe(true);
      await abrirFormulario(wrapper);
      expect(no('[data-contratar-enviar]')).toBeNull();

      aviso.querySelector('button').click();
      await flushPromises();
      expect(router.push).toHaveBeenCalledWith({
        name: 'settings_applications',
      });
      wrapper.unmount();
    });

    it('tells whoever is not an admin to warn the admin, with no button', async () => {
      papel.admin = false;
      const wrapper = await montar();

      const aviso = no('[data-falta-chave-de-ia]');
      expect(aviso.textContent).toContain(
        'AGENTS.CONTRATADOS.MODELO.SEM_CHAVE_DE_IA.TEXTO_SEM_ADMIN'
      );
      expect(aviso.querySelector('button')).toBeNull();
      wrapper.unmount();
    });
  });

  it('shows no warning and lets hire when the account has its key (or the list fails)', async () => {
    const wrapper = await montar();
    expect(no('[data-falta-chave-de-ia]')).toBeNull();
    expect(no('[data-contratar]').disabled).toBe(false);
    wrapper.unmount();

    api.lista.mockRejectedValue(new Error('Network Error'));
    const semLista = await montar();
    expect(no('[data-falta-chave-de-ia]')).toBeNull();
    expect(no('[data-contratar]').disabled).toBe(false);
    semLista.unmount();
  });

  it('says "try again" at the top when the request does not reach the server', async () => {
    api.contratar.mockRejectedValue(new Error('Network Error'));
    const wrapper = await montar();
    await abrirFormulario(wrapper);
    await preencher();
    await enviar();

    expect(no('[data-erro-do-formulario]').textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.GENERICO'
    );
    expect(invalido('nome_corretora')).toBe(false);
    wrapper.unmount();
  });

  it('does not offer "Contratar" for a model the screen does not know', async () => {
    const wrapper = await montar('outro_modelo');

    expect(wrapper.find('[data-contratar]').exists()).toBe(false);
    expect(wrapper.text()).toContain('AGENTS.CONTRATADOS.ERRO.INDISPONIVEL');
    wrapper.unmount();
  });
});
