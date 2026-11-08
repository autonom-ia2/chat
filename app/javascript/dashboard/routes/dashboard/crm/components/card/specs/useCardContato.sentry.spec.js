import * as Sentry from '@sentry/vue';
import { useCardContato } from '../useCardContato';

// Confere o EVENTO que o Sentry montaria (depois de breadcrumbs, escopo e
// processadores), não só os argumentos da chamada. Nenhum dado sai da máquina:
// o beforeSend guarda o evento e devolve null.
const api = vi.hoisted(() => ({ update: vi.fn() }));
vi.mock('dashboard/api/contacts', () => ({ default: api }));

const EMAIL = 'mariana.dado@exemplo.invalid';
const TELEFONE = '+5511912345678';
const NOME = 'Mariana Dado Pessoal';

describe('useCardContato — o que chega ao Sentry', () => {
  const eventos = [];

  beforeAll(() => {
    Sentry.init({
      dsn: 'https://chave@o0.ingest.sentry.io/0',
      defaultIntegrations: false,
      beforeSend: evento => {
        eventos.push(evento);
        return null;
      },
    });
  });

  afterAll(() => Sentry.close());

  it('sai só a classe e a pilha, sem mensagem, causa, breadcrumb nem extra', async () => {
    Sentry.addBreadcrumb({
      category: 'xhr',
      data: {
        method: 'GET',
        url: `/api/v1/accounts/1/contacts/search?q=${EMAIL}`,
      },
    });
    Sentry.getCurrentScope().setExtra('telefone', TELEFONE);
    const defeito = new TypeError(`não deu com ${NOME} <${EMAIL}>`, {
      cause: new Error(`telefone ${TELEFONE}`),
    });
    api.update.mockImplementation(() => {
      throw defeito;
    });
    const card = useCardContato();
    card.comecar({ id: 7, name: NOME, email: EMAIL });
    card.form.name = `${NOME} 2`;

    await card.salvar(chave => chave);
    await vi.waitFor(() => expect(eventos).toHaveLength(1));

    const [evento] = eventos;
    const [excecao] = evento.exception.values;
    expect(evento.exception.values).toHaveLength(1);
    expect(excecao.type).toBe('TypeError');
    // Sem mensagem, o SDK escreve o próprio texto padrão.
    expect(excecao.value).toBe('No error message');
    expect(excecao.stacktrace.frames.length).toBeGreaterThan(0);
    expect(evento.tags).toEqual({ tela: 'crm_card_contato' });
    expect(evento.breadcrumbs).toEqual([]);
    const tudo = JSON.stringify(evento);
    [EMAIL, TELEFONE, NOME, 'q='].forEach(dado =>
      expect(tudo).not.toContain(dado)
    );
  });
});
