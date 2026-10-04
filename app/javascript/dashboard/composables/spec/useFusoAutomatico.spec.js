import { ref, nextTick } from 'vue';
import {
  useFusoAutomatico,
  fusoDoNavegador,
  cidadeDoFuso,
} from '../useFusoAutomatico';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useStore } from 'dashboard/composables/store';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, vars) => `${key}${vars ? `:${vars.cidade}` : ''}`,
  }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount');
vi.mock('dashboard/composables/useAdmin');
vi.mock('dashboard/composables/store');

const flush = () =>
  new Promise(resolve => {
    setTimeout(resolve);
  });

const montar = ({ conta, admin = true, fuso = 'America/Cuiaba', falha }) => {
  const dispatch = falha
    ? vi.fn().mockRejectedValue(new Error('falhou'))
    : vi.fn().mockResolvedValue();
  useStore.mockReturnValue({ dispatch });
  const contaAtual = ref(conta);
  useAccount.mockReturnValue({
    currentAccount: contaAtual,
    accountScopedRoute: name => ({ name }),
  });
  useAdmin.mockReturnValue({ isAdmin: ref(admin) });
  vi.spyOn(Intl, 'DateTimeFormat').mockImplementation(() => ({
    resolvedOptions: () => ({ timeZone: fuso }),
  }));
  useFusoAutomatico();
  dispatch.contaAtual = contaAtual;
  return dispatch;
};

describe('useFusoAutomatico', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    useAlert.mockClear();
  });

  it('conta sem fuso ganha o do navegador e avisa com o atalho para trocar', async () => {
    const dispatch = montar({
      conta: { id: 1, custom_attributes: {}, settings: {} },
    });
    await flush();

    expect(dispatch).toHaveBeenCalledWith('accounts/update', {
      timezone: 'America/Cuiaba',
      options: { silent: true },
    });
    expect(useAlert).toHaveBeenCalledWith('FUSO_AUTOMATICO.AJUSTADO:Cuiabá', {
      type: 'link',
      to: { name: 'general_settings_index' },
      message: 'FUSO_AUTOMATICO.TROCAR',
    });
  });

  it('quem já escolheu um fuso fica com ele; só o campo de relatório é alinhado', async () => {
    const dispatch = montar({
      conta: {
        id: 1,
        custom_attributes: { timezone: 'America/Sao_Paulo' },
        settings: {},
      },
    });
    await flush();

    expect(dispatch).toHaveBeenCalledWith('accounts/update', {
      timezone: 'America/Sao_Paulo',
      options: { silent: true },
    });
  });

  it('conta com os dois campos preenchidos não é tocada', async () => {
    const dispatch = montar({
      conta: {
        id: 1,
        custom_attributes: { timezone: 'America/Sao_Paulo' },
        settings: { reporting_timezone: 'America/Sao_Paulo' },
      },
    });
    await flush();

    expect(dispatch).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });

  it('agente não grava fuso da conta', async () => {
    const dispatch = montar({
      conta: { id: 1, custom_attributes: {}, settings: {} },
      admin: false,
    });
    await flush();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('durante Primeiros passos não age: a própria tela já pergunta o fuso', async () => {
    const dispatch = montar({
      conta: {
        id: 1,
        custom_attributes: { onboarding_step: 'account_details' },
        settings: {},
      },
    });
    await flush();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('navegador sem fuso não grava nada', async () => {
    const dispatch = montar({
      conta: { id: 1, custom_attributes: {}, settings: {} },
      fuso: '',
    });
    await nextTick();
    await flush();

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('trocar de conta sem recarregar ajusta a outra conta também', async () => {
    const dispatch = montar({
      conta: { id: 1, custom_attributes: {}, settings: {} },
    });
    await flush();
    dispatch.contaAtual.value = { id: 2, custom_attributes: {}, settings: {} };
    await flush();

    expect(dispatch).toHaveBeenCalledTimes(2);
  });

  it('falha ao gravar fica em silêncio', async () => {
    montar({
      conta: { id: 1, custom_attributes: {}, settings: {} },
      falha: true,
    });
    await flush();

    expect(useAlert).not.toHaveBeenCalled();
  });
});

describe('fusoDoNavegador', () => {
  afterEach(() => vi.restoreAllMocks());

  it('recusa um nome que o navegador não reconhece', () => {
    const original = Intl.DateTimeFormat;
    vi.spyOn(Intl, 'DateTimeFormat').mockImplementation((locale, opts) => {
      if (opts?.timeZone) throw new RangeError('invalid');
      return { resolvedOptions: () => ({ timeZone: 'Lugar/Nenhum' }) };
    });

    expect(fusoDoNavegador()).toBeNull();
    expect(original).toBeDefined();
  });
});

describe('cidadeDoFuso', () => {
  it('mostra a cidade com espaço', () => {
    expect(cidadeDoFuso('America/Porto_Velho')).toBe('Porto Velho');
    expect(cidadeDoFuso('America/Sao_Paulo')).toBe('São Paulo');
  });
});
