import { PRESETS, sensitiveExtrasOn } from '../../customRoles/permissionMatrix';
import { cartoesProntos } from '../cartaoPronto';
import { ICONE_DA_CAPACIDADE } from '../guiada/useCartao';
import { ADMIN, CARLA, SEM_VER_VENDAS } from './quemMonta';

// #2308, especificação 7.6: selos, travas e capacidades dos cartões prontos, com os dois perfis fixos.
const tabela = giver =>
  Object.fromEntries(
    cartoesProntos(giver).map(cartao => [
      cartao.chave,
      {
        capacidades: cartao.capacidades.map(item => item.chave),
        selo: cartao.selo,
        travas: cartao.travas,
        fora: cartao.fora,
      },
    ])
  );

describe('cartões prontos', () => {
  it('Carla: tabela literal', () => {
    expect(tabela(CARLA)).toEqual({
      AGENT: {
        capacidades: ['PROPRIAS', 'VENDAS', 'SO_OLHA_CONTATOS'],
        selo: [],
        travas: [],
        fora: false,
      },
      SDR: {
        capacidades: ['PROPRIAS', 'CONTATOS_E_VENDAS', 'PROCURA'],
        selo: [],
        travas: [],
        fora: false,
      },
      SUPERVISOR: {
        capacidades: ['TODAS', 'CONTATOS_E_VENDAS', 'RELATORIOS'],
        selo: [],
        travas: [],
        fora: false,
      },
      SALES_MANAGER: {
        capacidades: ['TODAS', 'VENDAS_E_COLUNAS', 'RELATORIOS'],
        selo: [],
        travas: [
          { motivo: 'MISSING', chaves: ['crm_export'] },
          {
            motivo: 'DELEGATION',
            chaves: ['crm_metas_manage', 'sales_value_view'],
          },
        ],
        fora: false,
      },
      MARKETING: {
        capacidades: ['CAMPANHAS_DISPARA', 'CONTATOS', 'NAO_ATENDE'],
        selo: ['campaign_send', 'contact_export'],
        travas: [],
        fora: false,
      },
      OPERATIONS: {
        capacidades: ['TODAS', 'ARRUMA', 'CONTATOS'],
        selo: [],
        travas: [],
        fora: false,
      },
      READ_ONLY: {
        capacidades: ['SO_OLHA_AREAS', 'NAO_ATENDE'],
        selo: [],
        travas: [{ motivo: 'MISSING', chaves: ['insurance_view'] }],
        fora: false,
      },
      FINANCE: {
        capacidades: ['SO_OLHA_AREAS', 'NAO_ATENDE'],
        selo: [],
        travas: [{ motivo: 'DELEGATION', chaves: ['financial_view'] }],
        fora: true,
      },
    });
  });

  it('administrador: tabela literal, nada travado, o selo é o que a pronta traz', () => {
    const cartao = (capacidades, selo = []) => ({
      capacidades,
      selo,
      travas: [],
      fora: false,
    });
    expect(tabela(ADMIN)).toEqual({
      AGENT: cartao(['PROPRIAS', 'VENDAS', 'SO_OLHA_CONTATOS']),
      SDR: cartao(['PROPRIAS', 'CONTATOS_E_VENDAS', 'PROCURA']),
      SUPERVISOR: cartao(['TODAS', 'CONTATOS_E_VENDAS', 'RELATORIOS']),
      SALES_MANAGER: cartao(
        ['TODAS', 'VENDAS_E_COLUNAS', 'RELATORIOS'],
        ['crm_export', 'crm_metas_manage', 'sales_value_view']
      ),
      MARKETING: cartao(
        ['CAMPANHAS_DISPARA', 'CONTATOS', 'NAO_ATENDE'],
        ['campaign_send', 'contact_export']
      ),
      OPERATIONS: cartao(['TODAS', 'ARRUMA', 'CONTATOS']),
      READ_ONLY: cartao(['SO_OLHA_AREAS', 'NAO_ATENDE']),
      FINANCE: cartao(['SO_OLHA_AREAS', 'NAO_ATENDE']),
    });
  });

  // Os relatórios de atendimento contam como ver (Rodrigo, 28/10): entram no "Só olha" com as outras áreas.
  it('Só consulta só olha contatos, vendas, campanhas e relatórios', () => {
    const [leitura] = cartoesProntos(CARLA).filter(
      c => c.chave === 'READ_ONLY'
    );
    expect(leitura.capacidades[0]).toEqual({
      chave: 'SO_OLHA_AREAS',
      tipo: 'soOlha',
      areas: ['CONTACTS', 'CRM', 'CAMPAIGNS', 'REPORTS'],
    });
  });

  it('sensitiveExtrasOn(PRESETS.SDR()) = []', () => {
    expect(sensitiveExtrasOn(PRESETS.SDR())).toEqual([]);
  });

  it('até 3 capacidades; "só olha" e "não faz" nunca com o check', () => {
    [CARLA, ADMIN].forEach(giver =>
      cartoesProntos(giver).forEach(cartao => {
        expect(cartao.capacidades.length).toBeLessThanOrEqual(3);
        cartao.capacidades
          .filter(item => item.tipo !== 'pode')
          .forEach(item =>
            expect(ICONE_DA_CAPACIDADE[item.tipo]).not.toContain('check')
          );
      })
    );
    expect(ICONE_DA_CAPACIDADE.pode).toContain('i-lucide-check');
    expect(ICONE_DA_CAPACIDADE.soOlha).toContain('i-lucide-eye');
    expect(ICONE_DA_CAPACIDADE.ve).toContain('i-lucide-eye');
    expect(ICONE_DA_CAPACIDADE.naoFaz).toContain('i-lucide-x');
  });

  // Rodada 3: o corte conta as implicadas (crm_view), como o salvar e o GrantGuard#reach?.
  it('quem monta sem crm_view não leva nenhuma chave das vendas na pronta, nem as de editar', () => {
    const atendente = cartoesProntos(SEM_VER_VENDAS).find(
      cartao => cartao.chave === 'AGENT'
    );
    expect(atendente.corte.filter(chave => chave.startsWith('crm_'))).toEqual(
      []
    );
    expect(atendente.travas.flatMap(trava => trava.chaves)).toEqual(
      expect.arrayContaining(['crm_view', 'crm_manage_cards'])
    );
  });
});
