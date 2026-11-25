import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import GavetaDoContratado from '../../components/pagina/GavetaDoContratado.vue';
import ContratadoNaPagina from '../../components/pagina/ContratadoNaPagina.vue';

// #3211 (Tarefa 28) — a gaveta do contratado (o acesso ou os dados da corretora) e o bloco "Corretora e acesso" da
// página (mockup aprovado, estados 13 a 16).
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return { useMapGetter: () => computed(() => false) };
});
const papel = vi.hoisted(() => ({ admin: true }));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => papel.admin) }) };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const api = vi.hoisted(() => ({
  salvarDados: vi.fn(),
  conferirAcesso: vi.fn(),
}));
vi.mock('dashboard/api/autonomia/contratados', () => ({ default: api }));

const OK = {
  seguradora: 'universal',
  login_dica: 'co•••lo',
  estado: 'ok',
  motivo: null,
  conferido_em: '2026-11-25T12:00:00Z',
  so_cotacao: false,
};
const agente = (acesso = OK, extra = {}) => ({
  id: 9,
  name: 'Bia',
  status: 'active',
  enabled: true,
  contratado: {
    modelo: 'seguro_viagem_universal',
    nome_agente: 'Bia',
    nome_corretora: 'Corretora Exemplo',
    sobre_corretora: 'Corretora em Campinas desde 2010.',
    acesso,
  },
  ...extra,
});

const no = seletor => document.querySelector(seletor);
const digitar = async (seletor, valor) => {
  const campo = no(seletor);
  campo.value = valor;
  campo.dispatchEvent(new Event('input'));
  await nextTick();
};

const montarGaveta = props =>
  mount(GavetaDoContratado, {
    attachTo: document.body,
    props: { agente: agente(), nome: 'Bia', parte: 'corretora', ...props },
  });

describe('GavetaDoContratado (#3211)', () => {
  beforeEach(() => {
    papel.admin = true;
    api.salvarDados.mockResolvedValue({ data: agente() });
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('opens the access step by default', () => {
    const wrapper = montarGaveta({ parte: 'acesso' });
    expect(no('[role="dialog"]').textContent).toContain(
      'AGENTS.CONTRATADOS.ACESSO.TITULO'
    );
    expect(no('[data-acesso-conferido]')).not.toBeNull();
    wrapper.unmount();
  });

  it('changes only the brokerage, with a single "Salvar" button', async () => {
    const wrapper = montarGaveta();
    const gaveta = no('[role="dialog"]');

    expect(gaveta.textContent).toContain('AGENTS.CONTRATADOS.CORRETORA.TITULO');
    expect(no('[data-campo="nome_agente"]')).toBeNull();
    expect(no('[data-campo="nome_corretora"]').value).toBe('Corretora Exemplo');
    const botoes = [...gaveta.querySelectorAll('footer button')];
    expect(botoes).toHaveLength(1);
    expect(botoes[0].textContent).toContain(
      'AGENTS.CONTRATADOS.CORRETORA.SALVAR'
    );
    expect(botoes[0].className).toContain('w-full');
    expect(botoes[0].className).toContain('min-h-14');
    wrapper.unmount();
  });

  // O servidor confere as três chaves juntas (a ausente vira nil e é recusada): o nome do agente vai como está.
  it('sends the three fields, with the agent name as it is, and tells the page', async () => {
    const wrapper = montarGaveta();
    await digitar('[data-campo="nome_corretora"]', 'Corretora Nova');
    no('[data-salvar-corretora]').click();
    await flushPromises();

    expect(api.salvarDados).toHaveBeenCalledWith(9, {
      nomeAgente: 'Bia',
      nomeCorretora: 'Corretora Nova',
      sobreCorretora: 'Corretora em Campinas desde 2010.',
    });
    expect(alerta).toHaveBeenCalledWith('AGENTS.CONTRATADOS.CORRETORA.FEITO');
    expect(wrapper.emitted('atualizado')).toHaveLength(1);
    expect(wrapper.emitted('fechar')).toHaveLength(1);
    wrapper.unmount();
  });

  it('marks the field the server refused and keeps the drawer open', async () => {
    api.salvarDados.mockRejectedValue(
      Object.assign(new Error('422'), {
        response: {
          status: 422,
          data: { error: 'x', code: 'marcador', campo: 'nome_corretora' },
        },
      })
    );
    const wrapper = montarGaveta();
    no('[data-salvar-corretora]').click();
    await flushPromises();

    expect(
      no('[data-campo="nome_corretora"]').getAttribute('aria-invalid')
    ).toBe('true');
    expect(document.body.textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.MARCADOR'
    );
    expect(wrapper.emitted('fechar')).toBeUndefined();
    wrapper.unmount();
  });

  // O nome do agente não aparece nesta gaveta: a recusa dele não pode sumir sem mensagem.
  it('shows at the top a refusal of a field this drawer does not show', async () => {
    api.salvarDados.mockRejectedValue(
      Object.assign(new Error('422'), {
        response: {
          status: 422,
          data: { error: 'x', code: 'nome_agente', campo: 'nome_agente' },
        },
      })
    );
    const wrapper = montarGaveta();
    no('[data-salvar-corretora]').click();
    await flushPromises();

    expect(no('[data-erro-do-formulario]').textContent).toContain(
      'AGENTS.CONTRATADOS.ERRO.NOME_AGENTE'
    );
    expect(
      no('[data-campo="nome_corretora"]').getAttribute('aria-invalid')
    ).toBe('false');
    expect(wrapper.emitted('fechar')).toBeUndefined();
    wrapper.unmount();
  });
});

describe('ContratadoNaPagina (#3211)', () => {
  beforeEach(() => {
    papel.admin = true;
  });

  const montarBloco = props =>
    mount(ContratadoNaPagina, {
      props: { agente: agente(), nome: 'Bia', podeGerenciar: true, ...props },
    });

  it('lists what the agent does and the brokerage with the checked access', async () => {
    const wrapper = montarBloco();

    expect(wrapper.text()).toContain('AGENTS.CONTRATADOS.PAGINA.FAZ_TITULO');
    expect(wrapper.findAll('[data-faz] li')).toHaveLength(4);
    const bloco = wrapper.get('[data-corretora-e-acesso]');
    expect(bloco.text()).toContain('Corretora Exemplo');
    expect(bloco.text()).toContain('AGENTS.CONTRATADOS.PAGINA.CONFERIDO');
    expect(wrapper.find('[data-aviso-recusado]').exists()).toBe(false);

    await wrapper.get('[data-alterar-corretora]').trigger('click');
    await wrapper.get('[data-alterar-acesso-pagina]').trigger('click');
    expect(wrapper.emitted('alterarCorretora')).toHaveLength(1);
    expect(wrapper.emitted('alterarAcesso')).toHaveLength(1);
  });

  it('warns on the page when Universal refused the access later, with "Cadastrar a senha nova"', async () => {
    const wrapper = montarBloco({
      agente: agente({ ...OK, estado: 'recusado', motivo: 'acesso_recusado' }),
    });

    const aviso = wrapper.get('[data-aviso-recusado]');
    expect(aviso.text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.TITULO'
    );
    expect(aviso.text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.GARANTIA'
    );
    expect(wrapper.get('[data-corretora-e-acesso]').text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.RECUSADO'
    );
    await aviso.get('button').trigger('click');
    expect(aviso.get('button').text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.ACAO'
    );
    expect(wrapper.emitted('alterarAcesso')).toHaveLength(1);
  });

  it('marks the proposal item when the login only quotes', () => {
    const wrapper = montarBloco({
      agente: agente({ ...OK, so_cotacao: true }),
    });
    expect(wrapper.get('[data-faz]').text()).toContain(
      'AGENTS.CONTRATADOS.ACESSO.SO_COTA.ITEM'
    );
  });

  it('says it is answering on the channel right after the last step', () => {
    const wrapper = montarBloco({ atendendoNo: 'WhatsApp Vendas' });
    expect(wrapper.get('[data-contratado-atendendo]').text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.ATENDENDO'
    );
  });

  it('has no button for whoever only views', () => {
    const wrapper = montarBloco({
      podeGerenciar: false,
      agente: agente({ ...OK, estado: 'recusado', motivo: 'acesso_recusado' }),
    });
    expect(wrapper.find('button').exists()).toBe(false);
    expect(wrapper.get('[data-aviso-recusado]').text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.AVISO_RECUSADO.TITULO'
    );
  });

  // O acesso ao portal é só do administrador: quem gerencia sem ser administrador não abre uma gaveta sem saída.
  it('keeps the access buttons for administrators only', () => {
    papel.admin = false;
    const wrapper = montarBloco({
      agente: agente({ ...OK, estado: 'recusado', motivo: 'acesso_recusado' }),
    });

    expect(wrapper.find('[data-alterar-acesso-pagina]').exists()).toBe(false);
    expect(wrapper.get('[data-aviso-recusado]').find('button').exists()).toBe(
      false
    );
    expect(wrapper.get('[data-so-admin-pagina]').text()).toContain(
      'AGENTS.CONTRATADOS.ACESSO.SO_ADMIN'
    );
    expect(wrapper.find('[data-alterar-corretora]').exists()).toBe(true);
  });

  it('says the access is still missing before the first check', () => {
    const wrapper = montarBloco({ agente: agente(null) });
    expect(wrapper.get('[data-corretora-e-acesso]').text()).toContain(
      'AGENTS.CONTRATADOS.PAGINA.NAO_CONFERIDO'
    );
  });
});
