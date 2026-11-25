import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AcessoDaSeguradoraForm from '../../components/pagina/AcessoDaSeguradoraForm.vue';

// #3211 (Tarefa 28) — o passo 2: o login e a senha do portal da Universal (mockup aprovado, estados 05 a 11 e 16).
// O POST é só do administrador (Tarefa 21); quem gerencia sem ser administrador vê o estado, sem o formulário. A
// resposta nunca traz o login nem a senha, só `login_dica`, e a senha não fica na tela depois do envio.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});
const papel = vi.hoisted(() => ({ admin: true }));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => papel.admin) }) };
});
const api = vi.hoisted(() => ({ conferirAcesso: vi.fn() }));
vi.mock('dashboard/api/autonomia/contratados', () => ({ default: api }));

const SENHA = 'segredo de teste 1';
const OK = {
  seguradora: 'universal',
  login_dica: 'co•••lo',
  estado: 'ok',
  motivo: null,
  conferido_em: '2026-11-25T12:00:00Z',
};

const agente = acesso => ({
  id: 9,
  name: 'Bia',
  status: 'draft',
  contratado: {
    modelo: 'seguro_viagem_universal',
    nome_agente: 'Bia',
    nome_corretora: 'Corretora Exemplo',
    sobre_corretora: '',
    acesso,
  },
});

const no = seletor => document.querySelector(seletor);
const texto = () => document.body.textContent;
const digitar = async (seletor, valor) => {
  const campo = no(seletor);
  campo.value = valor;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};
const conferir = async () => {
  no('[data-conferir]').click();
  await flushPromises();
};
const preencher = async () => {
  await digitar('[data-acesso-login]', ' corretora.exemplo ');
  await digitar('[data-acesso-senha]', SENHA);
};
const senhaNaTela = () =>
  [...document.querySelectorAll('input, textarea')].some(
    campo => campo.value === SENHA
  ) || document.body.innerHTML.includes(SENHA);

const montar = (acesso = null, props = {}) =>
  mount(AcessoDaSeguradoraForm, {
    attachTo: document.body,
    props: {
      agente: agente(acesso),
      nome: 'Bia',
      emConfiguracao: true,
      ...props,
    },
  });

const recusa = dados =>
  Object.assign(new Error('422'), { response: { status: 422, data: dados } });

describe('AcessoDaSeguradoraForm (#3211)', () => {
  beforeEach(() => {
    papel.admin = true;
    api.conferirAcesso.mockResolvedValue({ data: OK });
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('starts empty right after hiring: created notice, step 2 and the two fields', () => {
    const wrapper = montar();

    expect(no('[role="dialog"]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.TITULO'
    );
    expect(no('[data-acesso-criada]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.CRIADA'
    );
    expect(no('[data-passo]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.PASSO'
    );
    expect(texto()).toContain('AGENTS.CONTRATADOS.ACESSO.EXPLICA');
    const senha = no('[data-acesso-senha]');
    expect(senha.getAttribute('type')).toBe('password');
    expect(senha.getAttribute('autocomplete')).toBe('off');
    expect(no('[data-acesso-login]').getAttribute('autocomplete')).toBe('off');
    expect(no('[data-conferir]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.CONFERIR'
    );
    wrapper.unmount();
  });

  it('does not send without the login and the password', async () => {
    const wrapper = montar();
    await conferir();

    expect(api.conferirAcesso).not.toHaveBeenCalled();
    expect(no('[data-acesso-login]').getAttribute('aria-invalid')).toBe('true');
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe('true');
    expect(texto()).toContain('AGENTS.CONTRATADOS.ACESSO.LOGIN.ERRO');
    expect(texto()).toContain('AGENTS.CONTRATADOS.ACESSO.SENHA.ERRO');
    wrapper.unmount();
  });

  it('posts exactly the login (without spaces at the ends) and the password as typed', async () => {
    const wrapper = montar();
    await preencher();
    await conferir();

    expect(api.conferirAcesso).toHaveBeenCalledTimes(1);
    expect(api.conferirAcesso).toHaveBeenCalledWith(9, {
      login: 'corretora.exemplo',
      senha: SENHA,
    });
    wrapper.unmount();
  });

  it('keeps no input with the password after the POST, also when it is refused', async () => {
    const wrapper = montar();
    await preencher();
    await conferir();
    expect(senhaNaTela()).toBe(false);
    wrapper.unmount();

    api.conferirAcesso.mockResolvedValue({
      data: { ...OK, estado: 'recusado', motivo: 'acesso_recusado' },
    });
    const outro = montar();
    await preencher();
    await conferir();
    expect(no('[data-acesso-senha]').value).toBe('');
    expect(no('[data-acesso-login]').value).toBe(' corretora.exemplo ');
    expect(senhaNaTela()).toBe(false);
    outro.unmount();

    api.conferirAcesso.mockRejectedValue(new Error('Network Error'));
    const terceiro = montar();
    await preencher();
    await conferir();
    expect(senhaNaTela()).toBe(false);
    terceiro.unmount();
  });

  it('shows the checked access with the login hint and goes on to the channel', async () => {
    const wrapper = montar();
    await preencher();
    await conferir();

    expect(no('[data-acesso-conferido]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.CONFERIDO.TITULO'
    );
    expect(texto()).toContain('co•••lo');
    expect(texto()).toContain('AGENTS.CONTRATADOS.ACESSO.SENHA.GUARDADA');
    expect(no('[data-passo]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.PASSO'
    );
    expect(no('[data-acesso-senha]')).toBeNull();
    expect(wrapper.emitted('conferido')).toEqual([[OK]]);

    no('[data-ir-para-o-canal]').click();
    await nextTick();
    expect(wrapper.emitted('escolherCanal')).toHaveLength(1);
    wrapper.unmount();
  });

  it('says Universal refused the login and password, and asks to type them again', async () => {
    api.conferirAcesso.mockResolvedValue({
      data: { ...OK, estado: 'recusado', motivo: 'acesso_recusado' },
    });
    const wrapper = montar();
    await preencher();
    await conferir();

    const erro = no('[data-acesso-erro]');
    expect(erro.textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.RECUSADO.TITULO'
    );
    expect(erro.textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.RECUSADO.GARANTIA'
    );
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe('true');
    expect(texto()).toContain('AGENTS.CONTRATADOS.ACESSO.SENHA.ESQUECEU');
    expect(no('[data-ir-para-o-canal]')).toBeNull();
    wrapper.unmount();
  });

  it('says Universal did not answer when the check timed out (200 nao_conferido/indisponivel)', async () => {
    api.conferirAcesso.mockResolvedValue({
      data: { ...OK, estado: 'nao_conferido', motivo: 'indisponivel' },
    });
    const wrapper = montar();
    await preencher();
    await conferir();

    expect(no('[data-acesso-erro]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.INDISPONIVEL.TITULO'
    );
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe(
      'false'
    );
    wrapper.unmount();
  });

  it('shows the server refusal on the field it names, or at the top', async () => {
    api.conferirAcesso.mockRejectedValue(
      recusa({ error: 'x', code: 'acesso_incompleto', campo: 'senha' })
    );
    const wrapper = montar();
    await preencher();
    await conferir();
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe('true');
    expect(texto()).toContain('AGENTS.CONTRATADOS.ERRO.ACESSO_INCOMPLETO');
    wrapper.unmount();

    api.conferirAcesso.mockRejectedValue(
      recusa({ error: 'x', code: 'indisponivel', campo: null })
    );
    const outro = montar();
    await preencher();
    await conferir();
    expect(no('[data-acesso-erro]').textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.INDISPONIVEL'
    );
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe(
      'false'
    );
    outro.unmount();
  });

  it('toggles the password eye with its label and aria-pressed', async () => {
    const wrapper = montar();
    const olho = no('[data-mostrar-senha]');
    expect(olho.getAttribute('aria-label')).toBe(
      'AGENTS.CONTRATADOS.ACESSO.SENHA.MOSTRAR'
    );
    expect(olho.getAttribute('aria-pressed')).toBe('false');

    olho.click();
    await nextTick();
    expect(no('[data-acesso-senha]').getAttribute('type')).toBe('text');
    expect(olho.getAttribute('aria-label')).toBe(
      'AGENTS.CONTRATADOS.ACESSO.SENHA.ESCONDER'
    );
    expect(olho.getAttribute('aria-pressed')).toBe('true');
    wrapper.unmount();
  });

  it('hides the password again after any answer and on "Alterar"', async () => {
    api.conferirAcesso.mockRejectedValue(new Error('Network Error'));
    const wrapper = montar();
    no('[data-mostrar-senha]').click();
    await nextTick();
    expect(no('[data-acesso-senha]').getAttribute('type')).toBe('text');
    await preencher();
    await conferir();
    expect(no('[data-acesso-senha]').getAttribute('type')).toBe('password');
    expect(no('[data-mostrar-senha]').getAttribute('aria-pressed')).toBe(
      'false'
    );
    wrapper.unmount();

    const conferido = montar(OK);
    no('[data-alterar-acesso]').click();
    await nextTick();
    no('[data-mostrar-senha]').click();
    await nextTick();
    await preencher();
    api.conferirAcesso.mockResolvedValue({
      data: { ...OK, estado: 'recusado', motivo: 'acesso_recusado' },
    });
    await conferir();
    expect(no('[data-acesso-senha]').getAttribute('type')).toBe('password');
    conferido.unmount();
  });

  it('drops the red ring once the new password is being typed', async () => {
    const wrapper = montar(
      { ...OK, estado: 'recusado', motivo: 'acesso_recusado' },
      { emConfiguracao: false }
    );
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe('true');
    await digitar('[data-acesso-senha]', 'n');
    expect(no('[data-acesso-senha]').getAttribute('aria-invalid')).toBe(
      'false'
    );
    wrapper.unmount();
  });

  it('opens on the refusal when Universal refused the access later (the page notice)', () => {
    const wrapper = montar(
      { ...OK, estado: 'recusado', motivo: 'acesso_recusado' },
      { emConfiguracao: false }
    );

    expect(no('[data-acesso-erro]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.RECUSADO.TITULO'
    );
    expect(no('[data-acesso-senha]')).not.toBeNull();
    expect(no('[data-passo]')).toBeNull();
    expect(no('[data-acesso-criada]')).toBeNull();
    wrapper.unmount();
  });

  it('lets whoever is not an administrator only read the state', async () => {
    papel.admin = false;
    const vazio = montar();
    expect(no('[data-acesso-login]')).toBeNull();
    expect(no('[data-acesso-senha]')).toBeNull();
    expect(no('[data-conferir]')).toBeNull();
    expect(no('[data-so-admin]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.SO_ADMIN'
    );
    vazio.unmount();

    const conferido = montar(OK);
    expect(no('[data-acesso-conferido]')).not.toBeNull();
    expect(no('[data-alterar-acesso]')).toBeNull();
    expect(no('[data-ir-para-o-canal]')).not.toBeNull();
    conferido.unmount();
  });

  it('changes a checked access from "Alterar", back to the fields', async () => {
    const wrapper = montar(OK);
    expect(no('[data-acesso-senha]')).toBeNull();
    no('[data-alterar-acesso]').click();
    await nextTick();
    expect(no('[data-acesso-senha]').value).toBe('');
    expect(no('[data-acesso-login]').value).toBe('');
    wrapper.unmount();
  });
});
