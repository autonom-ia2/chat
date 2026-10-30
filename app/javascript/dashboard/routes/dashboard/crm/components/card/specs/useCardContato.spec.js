import { useCardContato, payloadDoContato } from '../useCardContato';
import en from 'dashboard/i18n/locale/en/crm.json';
import ptBR from 'dashboard/i18n/locale/pt_BR/crm.json';

const api = vi.hoisted(() => ({ update: vi.fn() }));
vi.mock('dashboard/api/contacts', () => ({ default: api }));
// O evento que de fato sai ao Sentry é conferido em useCardContato.sentry.spec.js.
const sentry = vi.hoisted(() => ({ reportarSemDados: vi.fn() }));
vi.mock('dashboard/helper/sentryPrivacy', () => sentry);

const texto = (chave, valores) =>
  valores ? `${chave}:${JSON.stringify(valores)}` : chave;

const CONTATO = {
  id: 7,
  name: 'Mariana Costa',
  email: 'mariana@exemplo.invalid',
  phone_number: '+5511987654321',
  additional_attributes: {},
  custom_attributes: {},
};

// O caso do pedido: nome trocado, e-mail novo, telefone +55 com 11 dígitos,
// cidade, endereço e país preenchidos, cargo vazio.
const EDICAO = {
  name: 'Mariana C. Costa',
  email: 'nova@exemplo.invalid',
  phoneNumber: '+5511912345678',
  city: 'Campinas',
  address: 'Rua A, 1',
  country: 'Brasil',
};
const editar = (contato, edicao = EDICAO) => {
  const card = useCardContato();
  card.comecar(contato);
  Object.assign(card.form, edicao);
  return card;
};

const erroDaApi = (status, data) =>
  Object.assign(new Error(`Request failed with status code ${status}`), {
    isAxiosError: true,
    response: { status, data },
  });

describe('useCardContato — salvar', () => {
  beforeEach(() => {
    api.update.mockReset();
    sentry.reportarSemDados.mockReset();
  });

  it('grava só o que mudou e fecha a edição', async () => {
    api.update.mockResolvedValue({ data: {} });
    const card = editar(CONTATO);

    expect(await card.salvar(texto)).toBe(true);
    expect(api.update).toHaveBeenCalledWith(7, {
      name: 'Mariana C. Costa',
      email: 'nova@exemplo.invalid',
      phone_number: '+5511912345678',
      additional_attributes: { city: 'Campinas', country: 'Brasil' },
      custom_attributes: { address: 'Rua A, 1' },
    });
    expect(card.editando.value).toBe(false);
    expect(card.erro.value).toBe('');
  });

  it('422: mostra o motivo que a API devolve e aponta os campos', async () => {
    api.update.mockRejectedValue(
      erroDaApi(422, {
        message: 'E-mail já está em uso, Telefone já está em uso',
        attributes: ['email', 'phone_number'],
      })
    );
    const card = editar(CONTATO);

    expect(await card.salvar(texto)).toBe(false);
    expect(card.erro.value).toBe(
      'SAVE_ERROR_MOTIVO:{"motivo":"E-mail já está em uso, Telefone já está em uso"}'
    );
    expect(card.camposComErro.value).toEqual(['email', 'phoneNumber']);
    expect(card.editando.value).toBe(true);
    expect(sentry.reportarSemDados).not.toHaveBeenCalled();
  });

  it('resposta da API sem motivo: diz o código e que pode ter salvo', async () => {
    api.update.mockRejectedValue(erroDaApi(502, '<html>Bad Gateway</html>'));
    const card = editar(CONTATO);

    await card.salvar(texto);
    expect(card.erro.value).toBe('SAVE_ERROR_SERVIDOR:{"status":502}');
    expect(card.camposComErro.value).toEqual([]);
    expect(sentry.reportarSemDados).not.toHaveBeenCalled();
  });

  it('sem resposta (rede): diz que não falou com o servidor', async () => {
    api.update.mockRejectedValue(
      Object.assign(new Error('Network Error'), { isAxiosError: true })
    );
    const card = editar(CONTATO);

    await card.salvar(texto);
    expect(card.erro.value).toBe('SAVE_ERROR_REDE');
    expect(sentry.reportarSemDados).not.toHaveBeenCalled();
  });

  it('erro da própria tela vai ao Sentry pelo envio sem dados', async () => {
    const defeito = new TypeError('x.trim is not a function');
    api.update.mockImplementation(() => {
      throw defeito;
    });
    const card = editar(CONTATO);

    expect(await card.salvar(texto)).toBe(false);
    expect(card.erro.value).toBe('SAVE_ERROR_TELA');
    expect(sentry.reportarSemDados).toHaveBeenCalledWith(defeito, {
      tela: 'crm_card_contato',
    });
  });

  // Atributo personalizado da conta com a chave `address`/`job_title` pode
  // guardar número ou sim/não; antes, `.trim()` quebrava antes do PATCH.
  it('atributo que não é texto não quebra a gravação', async () => {
    api.update.mockResolvedValue({ data: {} });
    const card = editar(
      {
        ...CONTATO,
        additional_attributes: { city: null, country: 55 },
        custom_attributes: { address: 123, job_title: true },
      },
      { name: 'Mariana C. Costa' }
    );

    expect(card.form.address).toBe('123');
    expect(await card.salvar(texto)).toBe(true);
    expect(sentry.reportarSemDados).not.toHaveBeenCalled();
    expect(api.update).toHaveBeenCalledWith(7, { name: 'Mariana C. Costa' });
  });

  it('proxy devolvendo HTML no erro não quebra a mensagem', async () => {
    api.update.mockRejectedValue(erroDaApi(504, '<html>Gateway</html>'));
    const card = editar(CONTATO);

    await card.salvar(texto);
    expect(card.erro.value).toBe('SAVE_ERROR_SERVIDOR:{"status":504}');
  });
});

describe('textos do erro', () => {
  it('existem em en e pt_BR, com os mesmos parâmetros', () => {
    [
      ['SAVE_ERROR_MOTIVO', '{motivo}'],
      ['SAVE_ERROR_SERVIDOR', '{status}'],
      ['SAVE_ERROR_REDE', ''],
      ['SAVE_ERROR_TELA', ''],
      ['CAMPO_CONFIRA', ''],
    ].forEach(([chave, parametro]) =>
      [en, ptBR].forEach(catalogo => {
        const frase = catalogo.CRM_CARD.PESSOA[chave];
        expect(frase).toBeTruthy();
        expect(frase).toContain(parametro);
      })
    );
  });
});

describe('payloadDoContato', () => {
  it('não manda campo que só mudou espaço', () => {
    const inicial = {
      name: 'Ana',
      email: '',
      phoneNumber: '',
      jobTitle: '',
      city: '',
      address: '',
      country: '',
    };
    expect(payloadDoContato({ ...inicial, name: ' Ana ' }, inicial)).toEqual(
      {}
    );
  });
});
