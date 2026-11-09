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
  locked: true,
  already_lead_ids: [7],
};

const apiFalsa = () => ({
  getAudiences: vi.fn().mockResolvedValue({
    data: {
      payload: [LISTA_DA_API],
      meta: { has_more: true, next_before_at: 'T1', next_before_id: 4 },
    },
  }),
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
            lead_id: 3,
          },
        ],
      },
      meta: { total_count: 30, per_page: 25, next_after: 25, has_more: true },
    },
  }),
  addLeadsToAudience: vi.fn().mockResolvedValue({
    data: {
      payload: {
        audience: LISTA_DA_API,
        entered_lead_ids: [1],
        left_out: [{ lead_id: 2, reason_code: 'already_in_list' }],
        channels_off: [{ channel: 'email', count: 3 }],
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
    data: {
      payload: {
        ...LISTA_DA_API,
        id: 5,
        locked: false,
        skipped_contact_ids: [8, 9],
      },
    },
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
      enviada: true,
      jaNaLista: [7],
    });
    // Revisão do #2775, item 4: sem número de "já chamadas".
    expect(daLista({ ...LISTA_DA_API, called: 2 })).not.toHaveProperty(
      'chamadas'
    );
    expect(
      doMembro({ contact_id: 9, row_number: 2, lead_id: null, called: true })
    ).toEqual({
      contatoId: 9,
      linha: 2,
      nome: '',
      empresa: '',
      whatsapp: false,
      email: false,
      noCrm: false,
      leadId: null,
    });
  });

  it('a fonte da API chama as rotas das listas e devolve o formato da tela', async () => {
    const api = apiFalsa();
    const fonte = criarFonte({ api, crm: {} });

    const cursor = { em: 'T0', id: 9 };
    const pagina = await fonte.listas({ depois: cursor, empresaIds: [7, 8] });
    expect(api.getAudiences).toHaveBeenCalledWith({
      depois: cursor,
      leadIds: [7, 8],
    });
    expect(pagina.temMais).toBe(true);
    expect(pagina.depois).toEqual({ em: 'T1', id: 4 });
    expect(pagina.listas[0]).toMatchObject({ id: 4, enviada: true });

    // Revisão do #2775, item 2: as empresas vêm pelo cursor (a última linha).
    const aberta = await fonte.lista(4);
    expect(api.getAudience).toHaveBeenLastCalledWith(4, {});
    expect(aberta).toMatchObject({ total: 30, depois: 25, temMais: true });
    await fonte.lista(4, { depois: 25 });
    expect(api.getAudience).toHaveBeenLastCalledWith(4, { after: 25 });
    expect(aberta.membros[0]).toMatchObject({
      contatoId: 9,
      noCrm: true,
      leadId: 3,
    });

    const posta = await fonte.acrescentarNaLista({ listaId: 4, ids: [1, 2] });
    expect(api.addLeadsToAudience).toHaveBeenCalledWith(4, { leadIds: [1, 2] });
    expect(posta).toMatchObject({ publicoId: 4, nome: 'Padarias', n: 1 });
    expect(posta.fora).toEqual([{ id: 2, motivo: 'already_in_list' }]);
    expect(posta.canaisDesligados).toEqual([{ canal: 'email', n: 3 }]);

    const tirada = await fonte.tirarDaLista({ listaId: 4, empresaIds: [3] });
    expect(api.removeFromAudience).toHaveBeenCalledWith(4, {
      contactIds: [],
      leadIds: [3],
    });
    expect(tirada.tirados).toEqual([9]);

    await fonte.devolverNaLista({ listaId: 4, contatoIds: [9] });
    expect(api.restoreToAudience).toHaveBeenCalledWith(4, { contactIds: [9] });
    const copia = await fonte.copiarLista(4);
    expect(copia.lista).toMatchObject({ id: 5, enviada: false });
    expect(copia.deFora).toBe(2);
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
    const { listas, temMais } = await fonte.listas();

    expect(temMais).toBe(false);
    expect(listas.map(lista => lista.id)).toEqual(
      demoDasListas.LISTAS.map(lista => lista.id)
    );
    expect(listas[1].enviada).toBe(true);
  });
});
