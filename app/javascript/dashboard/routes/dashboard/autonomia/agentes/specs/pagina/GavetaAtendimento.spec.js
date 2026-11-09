import { mount, flushPromises } from '@vue/test-utils';
import GavetaAtendimento from '../../components/pagina/GavetaAtendimento.vue';
import {
  MAX_ENDERECO,
  lerAtendimento,
  temAtendimento,
} from '../../composables/useDadosDoAtendimento';

const store = vi.hoisted(() => ({ commit: vi.fn(), dispatch: vi.fn() }));
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    useMapGetter: () => computed(() => false),
  };
});
const alerta = vi.hoisted(() => vi.fn());
vi.mock('dashboard/composables', () => ({ useAlert: alerta }));
const api = vi.hoisted(() => ({ update: vi.fn() }));
vi.mock('dashboard/api/autonomia/agents', () => ({ default: api }));

// #1479 / #2723 — a gaveta "Endereço e telefone" grava no servidor (`config.atendimento`), sem localStorage. Telefone
// que o servidor recusa: a explicação dele aparece no próprio campo. Outra falha: o aviso de erro no rodapé.

const AGENTE = {
  id: 7,
  name: 'Bia',
  config: {
    response_window: 'always',
    atendimento: {
      endereco: 'Rua das Flores, 120',
      telefone: '+5511940001234',
    },
  },
};

const no = seletor => document.querySelector(seletor);
const endereco = () =>
  no('[data-campo-endereco] input, input[data-campo-endereco]');
const salvar = async () => {
  no('[data-salvar]').click();
  await flushPromises();
};

const montar = (agente = AGENTE) =>
  mount(GavetaAtendimento, {
    attachTo: document.body,
    props: { agente, nome: 'Bia' },
  });

const recusa = (mensagem, atributos = ['base']) => ({
  response: { status: 422, data: { message: mensagem, attributes: atributos } },
});
const CAMPOS = 'AGENTS.JORNADA.PAGINA.ATENDIMENTO.CAMPOS';
const SEM_TELEFONE = {
  ...AGENTE,
  config: { atendimento: { endereco: 'Rua', telefone: '' } },
};

describe('useDadosDoAtendimento · leitura', () => {
  it('lê o par do servidor, com as duas chaves sempre em texto', () => {
    expect(lerAtendimento(AGENTE)).toEqual({
      endereco: 'Rua das Flores, 120',
      telefone: '+5511940001234',
    });
    expect(lerAtendimento({ id: 1, config: {} })).toEqual({
      endereco: '',
      telefone: '',
    });
    expect(lerAtendimento(null)).toEqual({ endereco: '', telefone: '' });
  });

  it('não lê nada do navegador', () => {
    window.localStorage.setItem(
      'prototipo-1479-atendimento-9',
      JSON.stringify({ endereco: 'Velho', telefone: '+5511999999999' })
    );
    expect(lerAtendimento({ id: 9, config: {} })).toEqual({
      endereco: '',
      telefone: '',
    });
    window.localStorage.clear();
  });

  it('temAtendimento', () => {
    expect(temAtendimento({ endereco: '', telefone: '' })).toBe(false);
    expect(temAtendimento({ endereco: 'Rua', telefone: '' })).toBe(true);
  });
});

describe('GavetaAtendimento', () => {
  beforeEach(() => {
    api.update.mockReset();
    store.commit.mockReset();
    alerta.mockReset();
  });

  afterEach(() => {
    document.body.innerHTML = '';
  });

  it('abre com o que está gravado e limita o endereço ao teto do servidor', () => {
    montar();
    expect(endereco().value).toBe('Rua das Flores, 120');
    expect(endereco().getAttribute('maxlength')).toBe(String(MAX_ENDERECO));
  });

  it('salva no servidor só o atendimento, põe o agente devolvido na lista e fecha', async () => {
    const devolvido = { ...AGENTE, updated_at: '2026-11-09T12:00:00Z' };
    api.update.mockResolvedValue({ data: devolvido });
    const gaveta = montar();

    await salvar();

    expect(api.update).toHaveBeenCalledWith(7, {
      config: {
        atendimento: {
          endereco: 'Rua das Flores, 120',
          telefone: '+5511940001234',
        },
      },
    });
    expect(store.commit).toHaveBeenCalledWith(
      'autonomiaAgents/UPSERT_AUTONOMIAAGENTS',
      devolvido
    );
    expect(alerta).toHaveBeenCalledWith(
      'AGENTS.JORNADA.PAGINA.ATENDIMENTO.SALVO'
    );
    expect(gaveta.emitted('fechar')).toHaveLength(1);
  });

  it('telefone recusado pelo servidor (atributo telefone): o aviso no campo do telefone, sem fechar', async () => {
    api.update.mockRejectedValue(
      recusa('Telefone não parece certo.', ['telefone'])
    );
    const gaveta = montar();

    await salvar();

    expect(no('[data-campo-telefone-atendimento]').textContent).toContain(
      `${CAMPOS}.TELEFONE_RECUSADO`
    );
    expect(no('[data-erro]')).toBeNull();
    expect(gaveta.emitted('fechar')).toBeUndefined();
    expect(alerta).not.toHaveBeenCalled();
  });

  it('endereço recusado (atributo endereco): o aviso no campo do endereço, mesmo com telefone', async () => {
    api.update.mockRejectedValue(
      recusa('Endereço está longo demais.', ['endereco'])
    );
    montar();

    await salvar();

    expect(no('[data-dados-do-atendimento]').textContent).toContain(
      `${CAMPOS}.ENDERECO_RECUSADO`
    );
    expect(no('[data-campo-telefone-atendimento]').textContent).not.toContain(
      `${CAMPOS}.TELEFONE_RECUSADO`
    );
    expect(no('[data-erro]')).toBeNull();
  });

  it('recusa de outro atributo, mesmo com telefone preenchido: a explicação do servidor no rodapé', async () => {
    api.update.mockRejectedValue(recusa('Não deu para ler. Nada foi salvo.'));
    montar();

    await salvar();

    expect(no('[data-erro]').textContent).toContain(
      'Não deu para ler. Nada foi salvo.'
    );
    expect(no('[data-campo-telefone-atendimento]').textContent).not.toContain(
      'Não deu para ler.'
    );
  });

  it('falha sem explicação (rede): o aviso de erro no rodapé', async () => {
    api.update.mockRejectedValue(new Error('Network Error'));
    const gaveta = montar();

    await salvar();

    expect(no('[data-erro]').textContent).toContain(
      'AGENTS.JORNADA.PAGINA.ATENDIMENTO.ERRO'
    );
    expect(gaveta.emitted('fechar')).toBeUndefined();
  });

  it('enquanto salva, o telefone fica bloqueado', async () => {
    api.update.mockReturnValue(new Promise(() => {}));
    montar();

    no('[data-salvar]').click();
    await flushPromises();

    expect(no('[data-campo-telefone-atendimento]').hasAttribute('inert')).toBe(
      true
    );
  });

  it('telefone incompleto não salva e leva o foco ao campo', async () => {
    montar(SEM_TELEFONE);
    const campo = no('input[data-numero-do-telefone]');
    campo.value = '1199';
    campo.dispatchEvent(new Event('input', { bubbles: true }));
    await flushPromises();

    await salvar();

    expect(api.update).not.toHaveBeenCalled();
    expect(document.activeElement).toBe(campo);
    expect(no('[data-campo-telefone-atendimento]').textContent).toContain(
      `${CAMPOS}.TELEFONE_INCOMPLETO`
    );
  });
});
