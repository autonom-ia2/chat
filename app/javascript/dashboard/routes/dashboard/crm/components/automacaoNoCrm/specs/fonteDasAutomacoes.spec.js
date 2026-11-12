import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import CrmKanbanAPI from 'dashboard/api/crmKanban';
import {
  DATAS_DO_ENSAIO,
  EVENTO_REUNIAO_PELO_EMAIL,
  criarFonteFalsa,
  juntarAtividades,
} from '../fonteDasAutomacoes';
import { diaCurto, diaEHora, horaCurta } from '../datas';

// #2414 F6.3/F6.5 e #2710 — a fonte falsa do protótipo devolve o mesmo formato
// que a API vai devolver, e `?demo=vazio` esvazia tudo.
vi.mock('dashboard/api/crmKanban', () => ({
  default: { getContactOpportunities: vi.fn() },
}));

const { t } = withFullI18n('pt_BR').global;
const fonte = criarFonteFalsa({ t });
const vazia = criarFonteFalsa({ t, vazio: true });
const ganho = { id: 7, status: 'won', contact: { id: 3, name: 'Maria Souza' } };
const novoDeCliente = {
  id: 8,
  status: 'open',
  contact: { id: 3, name: 'Maria Souza', contact_type: 'customer' },
};

describe('fonte falsa das automações no CRM', () => {
  it('lista o que age no card, com a espera e a data', async () => {
    const itens = await fonte.automacoesDoCard({ id: 1 });
    expect(itens.map(item => item.nome)).toEqual([
      'Lembrete de proposta',
      'Avisar a equipe se o cliente sumir',
      'Ligar no dia seguinte',
    ]);
    expect(itens[0]).toMatchObject({
      estado: 'espera',
      ate: DATAS_DO_ENSAIO.esperaAte,
    });
    expect(await fonte.pararNoCard({ id: 1 }, itens[0])).toBe(true);
  });

  it('junta as regras da etapa e as automações novas numa lista só', async () => {
    const itens = await fonte.automacoesDaEtapa(12);
    expect(itens.map(item => item.origem)).toEqual(['etapa', 'motor', 'motor']);
    expect(itens.map(item => item.quando)).toEqual(['entra', 'entra', 'sai']);
    expect(itens[2].ligada).toBe(false);
    expect(itens[1].rota).toEqual({ name: 'automacoes_lista' });
  });

  it('a reunião e a linha do tempo só existem no card ganho', async () => {
    expect(await fonte.reuniaoDoCard(ganho)).toEqual({
      inicio: DATAS_DO_ENSAIO.reuniao,
      nome: 'Maria',
    });
    expect(await fonte.reuniaoDoCard({ ...ganho, status: 'open' })).toBeNull();
    const [linha] = fonte.atividadesDoCard(ganho);
    expect(linha).toMatchObject({
      event_type: EVENTO_REUNIAO_PELO_EMAIL,
      payload: { by: 'client', starts_at: DATAS_DO_ENSAIO.reuniao },
      labels: { contact_name: 'Maria' },
    });
    expect(fonte.atividadesDoCard({ ...ganho, status: 'lost' })).toEqual([]);
  });

  it('o selo só vai no card aberto de quem já é cliente', () => {
    expect(fonte.jaCliente(novoDeCliente)).toEqual({
      comprouEm: DATAS_DO_ENSAIO.comprouEm,
      contatoId: 3,
    });
    expect(fonte.jaCliente({ ...novoDeCliente, status: 'won' })).toBeNull();
    expect(
      fonte.jaCliente({
        ...novoDeCliente,
        contact: { id: 3, contact_type: 'lead' },
      })
    ).toBeNull();
    expect(fonte.jaCliente({ id: 9, status: 'open' })).toBeNull();
  });

  it('acha o card ganho do contato na API de hoje', async () => {
    CrmKanbanAPI.getContactOpportunities.mockResolvedValueOnce({
      data: { payload: [{ id: 55, status: 'won' }] },
    });
    expect(await fonte.cardGanho({ contatoId: 3 })).toBe(55);
    expect(CrmKanbanAPI.getContactOpportunities).toHaveBeenCalledWith('3', {
      result: 'won',
    });

    CrmKanbanAPI.getContactOpportunities.mockResolvedValueOnce({
      data: { payload: [] },
    });
    expect(await fonte.cardGanho({ contatoId: 3 })).toBeNull();
  });

  it('com ?demo=vazio, tudo vem vazio', async () => {
    expect(await vazia.automacoesDoCard({ id: 1 })).toEqual([]);
    expect(await vazia.automacoesDaEtapa(12)).toEqual([]);
    expect(await vazia.reuniaoDoCard(ganho)).toBeNull();
    expect(vazia.atividadesDoCard(ganho)).toEqual([]);
    expect(vazia.jaCliente(novoDeCliente)).toBeNull();
  });

  it('as linhas extras entram na linha do tempo pela data', () => {
    const doCard = [
      { id: 2, created_at: '2026-11-12T10:00:00' },
      { id: 1, created_at: '2026-11-10T10:00:00' },
    ];
    const extra = { id: 'x', created_at: '2026-11-11T10:00:00' };
    expect(juntarAtividades(doCard, [extra]).map(item => item.id)).toEqual([
      2,
      'x',
      1,
    ]);
    expect(juntarAtividades(doCard, [])).toBe(doCard);
  });
});

describe('datas curtas', () => {
  it('fala o dia e a hora como as pessoas falam', () => {
    expect(diaCurto('2026-11-03T15:30:00', 'pt_BR')).toBe('03/11');
    expect(horaCurta('2026-11-15T10:00:00', { t, locale: 'pt_BR' })).toBe(
      '10h'
    );
    expect(horaCurta('2026-11-15T10:30:00', { t, locale: 'pt_BR' })).toBe(
      '10:30'
    );
    expect(diaEHora('2026-11-15T10:00:00', { t, locale: 'pt_BR' })).toBe(
      '15/11 às 10h'
    );
    expect(diaEHora('', { t, locale: 'pt_BR' })).toBe('');
  });
});
