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

const recusa = mensagem => ({
  response: { status: 422, data: { message: mensagem } },
});

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

  it('telefone recusado pelo servidor: a explicação dele no campo, sem fechar', async () => {
    api.update.mockRejectedValue(recusa('Este telefone não é válido.'));
    const gaveta = montar();

    await salvar();

    expect(no('[data-campo-telefone-atendimento]').textContent).toContain(
      'Este telefone não é válido.'
    );
    expect(no('[data-erro]')).toBeNull();
    expect(gaveta.emitted('fechar')).toBeUndefined();
    expect(alerta).not.toHaveBeenCalled();
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

  it('recusa sem telefone preenchido: a explicação vai ao rodapé', async () => {
    api.update.mockRejectedValue(recusa('O endereço está longo demais.'));
    montar({
      ...AGENTE,
      config: { atendimento: { endereco: 'Rua', telefone: '' } },
    });

    await salvar();

    expect(no('[data-erro]').textContent).toContain(
      'O endereço está longo demais.'
    );
  });
});
