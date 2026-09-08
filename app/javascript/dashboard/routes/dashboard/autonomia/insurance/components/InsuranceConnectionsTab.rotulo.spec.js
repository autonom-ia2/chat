import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import InsuranceConnectionsTab from './InsuranceConnectionsTab.vue';

// O NOME DO PRODUTO NA TELA — spec separado porque precisa do i18n REAL.
//
// `InsuranceConnectionsTab.spec.js` roda com `messages: {}` e assere nas chaves cruas, que é o
// certo para o resto: não amarra o teste à cópia. Aqui é o oposto — o que está sob teste É a cópia
// que o corretor lê, e com i18n vazio `t(chave, fallback)` devolve o fallback, o que faria este
// arquivo passar sem provar nada.
//
// O CASO REAL: o ramo 46. O AGGER o chama de "Aluguel"; o nosso slug diz `fianca_locaticia`, e
// fiança locatícia é OUTRO produto no portal (id 23). O corretor lia na tela um produto diferente
// do que ia cotar. O slug não pode mudar — já viajou para o banco — então o rótulo passou a viajar
// junto, vindo do adapter (`label`), que lê o portal.
withFullI18n();

const api = vi.hoisted(() => ({
  getConnection: vi.fn(),
  connect: vi.fn(),
  reconnect: vi.fn(),
  rescan: vi.fn(),
  removeConnection: vi.fn(),
}));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const conexaoCom = produto => ({
  provider: 'agger',
  status: 'ready',
  username_hint: 'co*******@exemplo.com.br',
  external_account_label: 'CORRETORA X',
  last_authenticated_at: new Date().toISOString(),
  last_healthcheck_at: new Date().toISOString(),
  last_capability_scan_at: new Date().toISOString(),
  encryption_available: true,
  capabilities: {
    products: [
      {
        platformRef: '46',
        labelConfidence: 'confirmed',
        enabled: true,
        coveragePackages: [],
        insurers: [
          {
            code: '1',
            name: 'Porto',
            enabled: true,
            integrationStatus: 'ready',
          },
        ],
        ...produto,
      },
    ],
  },
});

const montar = async () => {
  const wrapper = mount(InsuranceConnectionsTab);
  await flushPromises();
  return wrapper;
};

describe('rótulo do produto na tela de Conexões', () => {
  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
  });

  it('usa o nome do portal quando o adapter manda label', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: conexaoCom({ product: 'fianca_locaticia', label: 'Aluguel' }),
      },
    });
    const wrapper = await montar();
    expect(wrapper.text()).toContain('Aluguel');
    // A tradução do slug é justamente o produto ERRADO. Se ela aparecer, o defeito voltou.
    expect(wrapper.text()).not.toContain('Fiança locatícia');
  });

  // Conexão gravada antes de o adapter mandar `label`. Sem a rede do i18n, a tela mostraria
  // `fianca_locaticia` cru para quem não reconectou ainda.
  it('sem label do adapter, traduz o slug em vez de mostrá-lo cru', async () => {
    api.getConnection.mockResolvedValue({
      data: { payload: conexaoCom({ product: 'auto', platformRef: '31' }) },
    });
    const wrapper = await montar();
    expect(wrapper.text()).toContain('Automóvel');
    expect(wrapper.text()).not.toContain('auto ');
  });

  // A FRONTEIRA MUDOU DE FORMA. A tradução do adapter no Rails era uma tabela de 13 chaves: o que
  // faltava nela — `platformRef`, `labelConfidence`, `integrationStatus` — passava batido em
  // camelCase, e este componente foi escrito contra isso. Com a tradução mecânica tudo chega em
  // snake_case, e todos os fixtures deste arquivo continuam em camelCase: eles passariam verdes
  // com a tela quebrada. Estes dois exemplos são a única prova do formato NOVO.
  it('le o codigo do ramo em snake_case, como o Rails passou a mandar', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: conexaoCom({
          product: 'ramo_777',
          label: 'Drone',
          platform_ref: '777',
          label_confidence: 'confirmed',
        }),
      },
    });
    const wrapper = await montar();
    expect(wrapper.text()).toContain('777');
  });

  // O asterisco avisa que o nome do ramo é chute do adapter. Lido pelo nome errado, ele some da
  // tela e o corretor passa a confiar num rótulo que ninguém confirmou.
  it('marca rotulo inferido vindo em snake_case', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: conexaoCom({
          product: 'ramo_888',
          label: 'Palpite',
          platform_ref: '888',
          label_confidence: 'inferred',
        }),
      },
    });
    const wrapper = await montar();
    expect(wrapper.text()).toContain('*');
  });

  // Produto que o adapter passou a cotar e o nosso i18n ainda não conhece. Antes desta mudança
  // ele aparecia como slug; agora o nome vem junto do dado.
  it('produto novo aparece com nome mesmo sem entrada no i18n', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: conexaoCom({
          product: 'ramo_777',
          label: 'Drone',
          platformRef: '777',
        }),
      },
    });
    const wrapper = await montar();
    expect(wrapper.text()).toContain('Drone');
    expect(wrapper.text()).not.toContain('ramo_777');
  });
});
