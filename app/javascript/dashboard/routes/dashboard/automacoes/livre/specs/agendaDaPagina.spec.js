import { flushPromises } from '@vue/test-utils';
import CrmBookingPagesAPI from 'dashboard/api/crmBookingPages';
import { comAgendas } from '../catalogo';
import { opcoesDosValores } from '../texto';
import { fraseDoValor } from '../frases';
import { linhasDoEnsaio } from '../ensaio';
import { useAgendasDaConta } from '../useAgendasDaConta';

// G44 (#2756) — o link da agenda de uma página escolhida (`agenda.<id>`).
const permitido = vi.hoisted(() => ({ sim: true }));
const flags = vi.hoisted(() => new Set(['crm_booking_v2']));
vi.mock('dashboard/composables/useCanManage', async () => {
  const { computed } = await import('vue');
  return { usePermissionGranted: () => computed(() => permitido.sim) };
});
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ isCloudFeatureEnabled: flag => flags.has(flag) }),
}));
vi.mock('dashboard/api/crmBookingPages', () => ({
  default: { get: vi.fn() },
}));

const t = (chave, valores) =>
  valores ? `${chave}(${Object.values(valores).join(',')})` : chave;
const catalogo = {
  valores: [{ caminho: 'contato.nome', frase: 'NOME' }],
  passos: [],
};
const paginas = [
  { id: 12, title: 'Implantação', ai_status: 'ativa' },
  { id: 13, title: 'Treinamento', ai_status: 'agenda_pausada' },
  { id: 14, title: 'Antiga', ai_status: 'pausada' },
  { id: 15, title: 'Sem ninguém', ai_status: 'sem_responsavel' },
];

describe('comAgendas', () => {
  it('a escolha oferece só a página que marca, com o nome dela', () => {
    const dados = comAgendas(catalogo, paginas, t, { soAsQueMarcam: true });

    expect(opcoesDosValores(dados, () => [], t)).toEqual([
      { value: 'contato.nome', label: 'NOME' },
      {
        value: 'agenda.12',
        label: 'AUTOMACAO_LIVRE.VALORES.AGENDA_DA_PAGINA(Implantação)',
      },
      {
        value: 'agenda.13',
        label: 'AUTOMACAO_LIVRE.VALORES.AGENDA_DA_PAGINA(Treinamento)',
      },
    ]);
  });

  it('a frase do passo mostra o nome de qualquer página, mesmo despublicada', () => {
    const dados = comAgendas(catalogo, paginas, t);

    expect(fraseDoValor('agenda.14', dados, t)).toBe(
      'AUTOMACAO_LIVRE.VALORES.AGENDA_DA_PAGINA(Antiga)'
    );
  });

  it('sem páginas, o catálogo fica como estava', () => {
    expect(comAgendas(catalogo, [], t)).toBe(catalogo);
  });
});

describe('o ensaio', () => {
  it('diz o motivo do link da agenda, como o motor', () => {
    const linhas = linhasDoEnsaio(
      [
        { id: 'm1', tipo: 'mensagem', faria: 'faltou_link_da_agenda' },
        { id: 'm2', tipo: 'mensagem', faria: 'sem_acesso_agenda' },
      ],
      () => 'frase',
      t
    );

    expect(linhas.map(linha => linha.aviso)).toEqual([
      'AUTOMACAO_LIVRE.ENSAIO.FALTOU_LINK_DA_AGENDA',
      'AUTOMACAO_LIVRE.ENSAIO.SEM_ACESSO_AGENDA',
    ]);
  });
});

describe('useAgendasDaConta', () => {
  beforeEach(() => {
    CrmBookingPagesAPI.get.mockReset();
    CrmBookingPagesAPI.get.mockResolvedValue({ data: { payload: paginas } });
    permitido.sim = true;
    flags.add('crm_booking_v2');
  });

  it('carrega as páginas para quem vê o agendamento', async () => {
    const { paginas: lidas, carregarAgendas } = useAgendasDaConta();
    carregarAgendas();
    await flushPromises();

    expect(lidas.value).toEqual(paginas);
  });

  it('sem agendamento_view, nem pede as páginas', async () => {
    permitido.sim = false;
    const { paginas: lidas, carregarAgendas } = useAgendasDaConta();
    await carregarAgendas();

    expect(CrmBookingPagesAPI.get).not.toHaveBeenCalled();
    expect(lidas.value).toEqual([]);
  });

  it('com o agendamento novo desligado, nem pede as páginas', async () => {
    flags.delete('crm_booking_v2');
    const { carregarAgendas } = useAgendasDaConta();
    await carregarAgendas();

    expect(CrmBookingPagesAPI.get).not.toHaveBeenCalled();
  });
});
