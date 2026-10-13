import adaptador, {
  esquecerTudo,
  motivoDaPausa,
  usosDaApi,
} from '../api/adaptadorHttp';
import { guardarArquivo } from '../api/arquivos';

const http = vi.hoisted(() => ({
  getInboxes: vi.fn(),
  getPrices: vi.fn(),
  getTemplates: vi.fn(),
  createTemplate: vi.fn(),
  updateTemplate: vi.fn(),
  deleteTemplate: vi.fn(),
  getUsage: vi.fn(),
  uploadMedia: vi.fn(),
  getCampaignPauses: vi.fn(),
  resumeCampaignPause: vi.fn(),
}));
vi.mock('dashboard/api/whatsappTemplates', () => ({ default: http }));

const ok = payload => Promise.resolve({ data: payload });

// Duas contas do WhatsApp: a 7 (caixas 7 e 8, a 7 precisa reconectar) e a 9.
const CAIXAS = [
  {
    id: 7,
    name: 'Atendimento',
    phone_number: '+1',
    group_id: 7,
    group_name: 'Matriz',
    reconnect: true,
    template_sends: { boas_vindas: 2 },
  },
  {
    id: 8,
    name: 'Vendas',
    phone_number: '+2',
    group_id: 7,
    group_name: 'Matriz',
    reconnect: false,
    template_sends: { boas_vindas: 3 },
  },
  {
    id: 9,
    name: 'Filial',
    phone_number: '+3',
    group_id: 9,
    group_name: 'Filial',
    reconnect: false,
    template_sends: {},
  },
];
const TEMPLATE = {
  id: '1001',
  name: 'boas_vindas',
  language: 'pt_BR',
  status: 'APPROVED',
  category: 'MARKETING',
  components: [{ type: 'BODY', text: 'Oi, {{1}}!' }],
  fields: { 1: 'cliente.primeiro_nome' },
};

beforeEach(() => {
  esquecerTudo();
  Object.values(http).forEach(fn => fn.mockReset());
  http.getInboxes.mockReturnValue(ok({ payload: CAIXAS }));
  http.getTemplates.mockImplementation(caixa =>
    ok({
      payload:
        caixa === 8
          ? [
              TEMPLATE,
              {
                ...TEMPLATE,
                id: '1002',
                name: 'apagando',
                status: 'PENDING_DELETION',
              },
            ]
          : [],
    })
  );
});

describe('adaptador HTTP de Modelos', () => {
  it('reads each WhatsApp account once, by a connected box, and sums the month sends', async () => {
    const modelos = await adaptador.listarModelos({ atualizar: true });

    expect(http.getTemplates).toHaveBeenCalledTimes(2);
    expect(http.getTemplates).toHaveBeenCalledWith(8, { refresh: true });
    expect(http.getTemplates).toHaveBeenCalledWith(9, { refresh: true });
    expect(modelos).toHaveLength(1);
    expect(modelos[0]).toMatchObject({
      id: '1001',
      conta: 7,
      caixa: 8,
      numeros: [7, 8],
      enviosNoMes: 5,
    });
    expect(await adaptador.listarNumeros()).toEqual([
      {
        id: 8,
        nome: 'Vendas',
        telefone: '+2',
        conta: { id: 7, nome: 'Matriz' },
        situacao: 'conectada',
      },
      {
        id: 9,
        nome: 'Filial',
        telefone: '+3',
        conta: { id: 9, nome: 'Filial' },
        situacao: 'conectada',
      },
    ]);
  });

  it('when "Atualizar" fails, shows the saved list and says why, without calling it new (#1382)', async () => {
    http.getTemplates.mockImplementation((caixa, opcoes = {}) => {
      if (caixa === 8 && opcoes.refresh) {
        return Promise.reject(
          Object.assign(new Error('sync'), {
            response: {
              status: 422,
              data: { error: 'sync_failed', code: 'permission_denied' },
            },
          })
        );
      }
      return ok({ payload: caixa === 8 ? [TEMPLATE] : [] });
    });

    const modelos = await adaptador.listarModelos({ atualizar: true });

    expect(http.getTemplates).toHaveBeenCalledWith(8, { refresh: true });
    expect(http.getTemplates).toHaveBeenCalledWith(8);
    expect(modelos).toHaveLength(1);
    expect(modelos.naoLeu).toEqual([]);
    expect(modelos.naoAtualizou).toEqual([
      { conta: 'Matriz', motivo: 'permission_denied' },
    ]);
  });

  it('keeps the list for a moment and reads again after a change', async () => {
    await adaptador.listarModelos();
    await adaptador.obterModelo('1001');
    expect(http.getTemplates).toHaveBeenCalledTimes(2);

    http.deleteTemplate.mockReturnValue(ok({}));
    const { nomeBloqueadoAte } = await adaptador.apagarModelo('1001');
    expect(http.deleteTemplate).toHaveBeenCalledWith(8, '1001');
    expect(new Date(nomeBloqueadoAte) > new Date()).toBe(true);
    await adaptador.listarModelos();
    expect(http.getTemplates).toHaveBeenCalledTimes(4);
  });

  it('creates one template per WhatsApp account, uploading the file by that account box', async () => {
    const local = guardarArquivo(
      new File(['x'], 'capa.jpg', { type: 'image/jpeg' })
    );
    http.uploadMedia.mockImplementation(caixa =>
      ok({ handle: `h-${caixa}`, blob_signed_id: `b-${caixa}` })
    );
    http.createTemplate.mockImplementation((caixa, corpo) =>
      ok({
        ...TEMPLATE,
        id: `novo-${caixa}`,
        name: corpo.name,
        status: 'PENDING',
      })
    );
    const rascunho = {
      nome: 'Boas-vindas',
      tipo: 'divulgacao',
      numeros: [8, 9],
      conteudo: {
        formato: 'padrao',
        topo: { tipo: 'foto', arquivo: 'capa.jpg', local },
        texto: [{ t: 'texto', v: 'Oi!' }],
        exemplos: {},
        rodape: '',
        botoes: [],
      },
    };

    const criados = await adaptador.criarModelo(rascunho);

    expect(criados.map(item => [item.id, item.situacao])).toEqual([
      ['novo-8', 'em_analise'],
      ['novo-9', 'em_analise'],
    ]);
    expect(http.createTemplate.mock.calls[0][1].components[0].example).toEqual({
      header_handle: ['h-8'],
    });
    expect(http.createTemplate.mock.calls[1][1].header_media).toEqual({
      handle: 'h-9',
      blob_signed_id: 'b-9',
    });
  });

  it('names the WhatsApp account that did not answer the list (#1387)', async () => {
    http.getTemplates.mockImplementation(caixa =>
      caixa === 9
        ? Promise.reject(
            Object.assign(new Error('fora'), { response: { status: 500 } })
          )
        : ok({ payload: [TEMPLATE] })
    );

    const modelos = await adaptador.listarModelos();

    expect(modelos).toHaveLength(1);
    expect(modelos.naoLeu).toEqual(['Filial']);
  });

  it('keeps the created template and names the account left without the request (#1387)', async () => {
    http.createTemplate.mockImplementation(caixa =>
      caixa === 9
        ? Promise.reject(
            Object.assign(new Error('meta'), {
              response: {
                status: 422,
                data: { error: 'meta_refused', message: 'Conta fora do ar.' },
              },
            })
          )
        : ok({ ...TEMPLATE, id: `novo-${caixa}`, status: 'PENDING' })
    );

    const criados = await adaptador.criarModelo({
      nome: 'Boas-vindas',
      tipo: 'aviso',
      numeros: [8, 9],
      conteudo: {
        formato: 'padrao',
        topo: { tipo: 'nenhum' },
        texto: [{ t: 'texto', v: 'Oi!' }],
        exemplos: {},
        rodape: '',
        botoes: [],
      },
    });

    expect(criados.map(item => item.id)).toEqual(['novo-8']);
    expect(criados.contasSemPedido).toEqual(['Filial']);
    expect(criados.falha.mensagem).toBe('Conta fora do ar.');
  });

  it('turns an API refusal into a readable error', async () => {
    http.createTemplate.mockRejectedValue({
      response: {
        status: 422,
        data: {
          error: 'name_taken',
          message: 'Já existe um modelo com este nome.',
        },
      },
    });

    await expect(
      adaptador.criarModelo({
        nome: 'x',
        tipo: 'aviso',
        numeros: [9],
        conteudo: {
          formato: 'padrao',
          topo: { tipo: 'nenhum' },
          texto: [],
          exemplos: {},
          rodape: '',
          botoes: [],
        },
      })
    ).rejects.toMatchObject({
      codigo: 'name_taken',
      mensagem: 'Já existe um modelo com este nome.',
    });
  });

  it('lists paused campaigns with their template and reason', async () => {
    http.getCampaignPauses.mockReturnValue(
      ok({
        payload: [
          {
            id: 31,
            source: 'template',
            reason_code: 'template_not_approved',
            details: {
              template_name: 'boas_vindas',
              language: 'pt_BR',
              status: 'PAUSED',
            },
            campaign: { id: 4, title: 'Outubro', inbox_id: 7 },
            ready_to_resume: true,
          },
        ],
      })
    );

    expect(await adaptador.listarCampanhasParadas()).toEqual([
      {
        id: 4,
        pausaId: 31,
        nome: 'Outubro',
        modeloId: '1001',
        modeloNome: 'boas_vindas',
        motivo: 'modelo_pausado',
        podeRetomar: true,
      },
    ]);
  });

  it('translates every pause reason', () => {
    const motivo = (reason_code, extras = {}) =>
      motivoDaPausa({ source: 'template', reason_code, ...extras });
    expect(
      motivo('template_not_approved', { details: { status: 'REJECTED' } })
    ).toBe('modelo_recusado');
    expect(
      motivo('template_not_approved', { details: { status: 'PENDING' } })
    ).toBe('modelo_em_analise');
    expect(motivo('template_category_changed')).toBe('tipo_mudou');
    expect(motivo('template_structure_changed')).toBe('modelo_mudou');
    expect(motivo('template_missing')).toBe('modelo_apagado');
    expect(motivo('template_format_unsupported')).toBe('formato_nao_vai');
    expect(
      motivoDaPausa({ source: 'system', reason_code: 'template_unverifiable' })
    ).toBe('nao_conferido');
    // #1382: o sistema não achou o modelo; e topo de mídia sem o arquivo guardado.
    expect(
      motivoDaPausa({ source: 'system', reason_code: 'template_missing' })
    ).toBe('modelo_apagado');
    expect(motivo('template_media_missing')).toBe('arquivo_do_topo');
  });

  it('shows usage the person can see and only a notice for the rest', () => {
    const usos = usosDaApi(
      {
        campaigns: [
          { id: 3, title: 'Outubro', scheduled_at: '2026-10-20T12:00:00Z' },
        ],
        booking_pages: [{ id: 2, title: 'Consultas' }],
        follow_ups: [{ id: 5, title: 'Retorno', card_id: 77, due_at: null }],
        uso_oculto: true,
      },
      'pt_BR'
    );
    expect(usos.map(uso => [uso.tipo, uso.nome, uso.agendado])).toEqual([
      ['campanha', 'Outubro', true],
      ['agendamento', 'Consultas', true],
      ['crm', 'Retorno', true],
      ['oculto', '', true],
    ]);
    expect(usos[2].rota).toEqual({
      name: 'crm_kanban_index',
      query: { card_id: '77' },
    });
  });

  it('gives the price per send and the free replies of the month, or nothing without a table', async () => {
    http.getPrices.mockReturnValue(
      ok({
        payload: {
          currency: 'BRL',
          prices: {
            marketing: '0.3217',
            utility: '0.035',
            authentication: '0.035',
            service: null,
          },
          free_tier: { service: { messages: 1000 } },
          service_usage: [{ inbox_id: 8, name: 'Vendas', messages: 1001 }],
        },
      })
    );

    expect(await adaptador.custoPorEnvio('divulgacao')).toEqual({
      valor: 0.3217,
      moeda: 'BRL',
    });
    expect(await adaptador.custoPorEnvio('aviso')).toEqual({
      valor: 0.035,
      moeda: 'BRL',
    });
    expect(await adaptador.custoPorEnvio('resposta')).toBeNull();
    expect(await adaptador.obterFranquia()).toEqual({
      limite: 1000,
      numeros: [{ id: 8, nome: 'Vendas', usadas: 1001 }],
    });
  });

  it('keeps the AI entry points closed until delivery E', async () => {
    await expect(adaptador.criarComIA({})).rejects.toThrow('ia_indisponivel');
    expect(await adaptador.obterCatalogo()).toBeNull();
    expect(await adaptador.listarFormularios()).toEqual([]);
  });
});

describe('caixa sem modelos (message_templates = {} em produção)', () => {
  it('lists nothing, without error, when the API answers an empty payload', async () => {
    http.getTemplates.mockImplementation(() => ok({ payload: [] }));

    const modelos = await adaptador.listarModelos({ atualizar: true });

    expect(modelos).toHaveLength(0);
    expect(modelos.naoLeu).toEqual([]);
  });
});
