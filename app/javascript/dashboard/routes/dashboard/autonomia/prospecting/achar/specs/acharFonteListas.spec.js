import { criarFonte } from '../utils/acharFonte';
import { daLista, doMembro } from '../utils/acharFonteListas';
import * as demoDasListas from '../demo/acharListasDemo';

// #2775 — F6: as listas na fonte, no mesmo formato na demonstração e na API.
const LISTA_DA_API = {
  id: 4,
  name: 'Padarias',
  companies: 12,
  whatsapp: 9,
  email: 5,
  in_crm: 3,
  called: 2,
  locked: true,
};

const apiFalsa = () => ({
  getAudiences: vi
    .fn()
    .mockResolvedValue({ data: { payload: [LISTA_DA_API] } }),
  getAudience: vi.fn().mockResolvedValue({
    data: {
      payload: {
        ...LISTA_DA_API,
        members: [
          {
            contact_id: 9,
            row_number: 1,
            name: 'Ana',
            company_name: 'Padaria Um',
            whatsapp: true,
            email: false,
            in_crm: true,
            called: false,
            lead_id: 3,
          },
        ],
      },
      meta: { total_count: 1, per_page: 25 },
    },
  }),
  addLeadsToAudience: vi.fn().mockResolvedValue({
    data: {
      payload: {
        audience: LISTA_DA_API,
        entered_lead_ids: [1],
        left_out: [{ lead_id: 2, reason_code: 'already_in_list' }],
      },
    },
  }),
  removeFromAudience: vi.fn().mockResolvedValue({
    data: { payload: { audience: LISTA_DA_API, removed_contact_ids: [9] } },
  }),
  restoreToAudience: vi.fn().mockResolvedValue({
    data: { payload: { audience: LISTA_DA_API } },
  }),
  copyAudience: vi.fn().mockResolvedValue({
    data: { payload: { ...LISTA_DA_API, id: 5, locked: false } },
  }),
  getLeadAudiences: vi.fn().mockResolvedValue({
    data: { payload: [{ id: 4, name: 'Padarias', locked: false }] },
  }),
});

describe('acharFonteListas', () => {
  it('traduz a lista e a empresa da API para os nomes da tela', () => {
    expect(daLista(LISTA_DA_API)).toEqual({
      id: 4,
      nome: 'Padarias',
      empresas: 12,
      whatsapp: 9,
      email: 5,
      noCrm: 3,
      chamadas: 2,
      enviada: true,
    });
    expect(
      doMembro({ contact_id: 9, row_number: 2, lead_id: null })
    ).toMatchObject({ contatoId: 9, linha: 2, leadId: null, whatsapp: false });
  });

  it('a fonte da API chama as rotas das listas e devolve o formato da tela', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ api, crm: {} });

    expect((await fonte.listas())[0]).toMatchObject({ id: 4, enviada: true });
    const aberta = await fonte.lista(4, 2);
    expect(api.getAudience).toHaveBeenCalledWith(4, { page: 2 });
    expect(aberta.membros[0]).toMatchObject({
      contatoId: 9,
      noCrm: true,
      leadId: 3,
    });
    expect(aberta.total).toBe(1);

    const posta = await fonte.acrescentarNaLista({ listaId: 4, ids: [1, 2] });
    expect(api.addLeadsToAudience).toHaveBeenCalledWith(4, { leadIds: [1, 2] });
    expect(posta).toMatchObject({ publicoId: 4, nome: 'Padarias', n: 1 });
    expect(posta.fora).toEqual([{ id: 2, motivo: 'already_in_list' }]);

    const tirada = await fonte.tirarDaLista({ listaId: 4, empresaIds: [3] });
    expect(api.removeFromAudience).toHaveBeenCalledWith(4, {
      contactIds: [],
      leadIds: [3],
    });
    expect(tirada.tirados).toEqual([9]);

    await fonte.devolverNaLista({ listaId: 4, contatoIds: [9] });
    expect(api.restoreToAudience).toHaveBeenCalledWith(4, { contactIds: [9] });
    expect(await fonte.copiarLista(4)).toMatchObject({ id: 5, enviada: false });
    expect(await fonte.listasDaEmpresa(3)).toEqual([
      { id: 4, nome: 'Padarias', enviada: false },
    ]);
  });

  it('a recusa da API leva o código do servidor', async () => {
    const api = apiFalsa();
    api.addLeadsToAudience.mockRejectedValue({
      response: {
        data: { code: 'prospecting.audience.audience_locked', left_out: [] },
      },
    });
    const fonte = criarFonte({ api, crm: {} });

    await expect(
      fonte.acrescentarNaLista({ listaId: 4, ids: [1] })
    ).rejects.toMatchObject({
      codigo: 'prospecting.audience.audience_locked',
    });
  });

  it('a demonstração usa os dados inventados e não grava nada', async () => {
    const fonte = criarFonte({
      demo: 'listas',
      carregarDemo: async () => ({}),
      atraso: 0,
    });
    const listas = await fonte.listas();

    expect(listas.map(lista => lista.id)).toEqual(
      demoDasListas.LISTAS.map(lista => lista.id)
    );
    expect(listas[1].enviada).toBe(true);
  });
});
