import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount, flushPromises } from '@vue/test-utils';
import InsuranceConnectionsTab from './InsuranceConnectionsTab.vue';

const api = vi.hoisted(() => ({
  getConnection: vi.fn(),
  connect: vi.fn(),
  reconnect: vi.fn(),
  rescan: vi.fn(),
  removeConnection: vi.fn(),
}));
vi.mock('dashboard/api/autonomiaInsurance', () => ({ default: api }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const blank = {
  provider: 'agger',
  status: 'not_configured',
  capabilities: {},
  encryption_available: true,
};
const ready = {
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
        product: 'auto',
        platformRef: '31',
        labelConfidence: 'confirmed',
        enabled: true,
        coveragePackages: ['Prata'],
        insurers: [
          {
            code: '47',
            name: 'Justos',
            enabled: true,
            integrationStatus: 'ready',
          },
          {
            code: '13',
            name: 'Mitsui',
            enabled: false,
            integrationStatus: 'auth_required',
          },
        ],
      },
      {
        product: 'vida',
        platformRef: '91',
        labelConfidence: 'inferred',
        enabled: false,
        coveragePackages: ['Prata'],
        insurers: [],
      },
    ],
  },
};

const mountTab = async () => {
  const wrapper = mount(InsuranceConnectionsTab);
  await flushPromises();
  return wrapper;
};

describe('InsuranceConnectionsTab (API)', () => {
  beforeEach(() => {
    Object.values(api).forEach(fn => fn.mockReset());
  });

  it('loads the connection on mount and shows the form when not configured', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: blank } });
    const wrapper = await mountTab();
    expect(api.getConnection).toHaveBeenCalledTimes(1);
    expect(wrapper.find('#insurance-agger-username').exists()).toBe(true);
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.NOT_CONFIGURED'
    );
  });

  it('posts credentials once, clears the password and renders the real capability map', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: blank } });
    api.connect.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();

    await wrapper
      .find('#insurance-agger-username')
      .setValue('corretora@exemplo.com.br');
    await wrapper.find('#insurance-agger-password').setValue('segredo');
    await wrapper
      .find('button[label="INSURANCE.CONNECTION.ACTIONS.CONNECT"]')
      .trigger('click');
    await flushPromises();

    expect(api.connect).toHaveBeenCalledWith({
      username: 'corretora@exemplo.com.br',
      password: 'segredo',
    });
    expect(wrapper.html()).not.toContain('segredo');
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.STATES.READY');
    expect(wrapper.text()).toContain('co*******@exemplo.com.br');
    expect(wrapper.text()).toContain('CORRETORA X');
    // t(chave, fallback): sem mensagens no teste, o rótulo do produto cai no slug — é o comportamento
    // desejado para ramos ainda sem nome (ramo_100). O que importa é o mapa renderizado.
    //
    // A contagem mostra o DENOMINADOR quando há seguradora pendente: `auto` no fixture tem Justos
    // pronta e Mitsui recusada, e "1 seguradora disponível" esconderia que são 2 no total.
    expect(wrapper.text()).toContain(
      'INSURANCE.CAPABILITIES.INSURERS_OF_TOTAL'
    );
    // E a recusada aparece PELO NOME, não como contagem anônima.
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.MONEY_LEFT');
    expect(wrapper.find('#insurance-agger-password').exists()).toBe(false);
  });

  // CRITÉRIO 1.1 — a tela não atribui ao corretor uma falha que não é dele.
  //
  // Este exemplo exigia `AUTH_REQUIRED_HINT` sempre que o status fosse `auth_required`, e esse hint
  // manda conferir usuário e senha. Como QUALQUER 403 virava `auth_required`, uma sessão derrubada
  // por login no navegador pedia troca de senha — aconteceu duas vezes em 05/09/2026, com a
  // credencial certa nas duas. Agora quem decide a mensagem é a CAUSA, não o status.
  it('pede a senha de volta quando o portal recusou a credencial', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...blank,
          status: 'auth_required',
          last_error: 'credential_rejected: invalid credentials',
          failure: {
            cause: 'credential_rejected',
            actor: 'broker',
            retryable: false,
          },
          username_hint: 'x***@y.com',
        },
      },
    });
    api.reconnect.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.AUTH_REQUIRED'
    );
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.FAILURES.CREDENTIAL_REJECTED'
    );
    // O corretor lê a frase que diz o que FAZER. O motivo técnico continua gravado em `last_error`
    // e no log; na tela ele só expunha a URL interna do portal e não ajudava ninguém.
    expect(wrapper.text()).not.toContain(
      'credential_rejected: invalid credentials'
    );

    await wrapper
      .find('button[label="INSURANCE.CONNECTION.ACTIONS.RECONNECT"]')
      .trigger('click');
    await flushPromises();
    expect(api.reconnect).toHaveBeenCalledTimes(1);
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.STATES.READY');
  });

  it('blocks connecting when the encryption vault is unavailable', async () => {
    api.getConnection.mockResolvedValue({
      data: { payload: { ...blank, encryption_available: false } },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.ENCRYPTION_UNAVAILABLE'
    );
    expect(
      wrapper
        .find('button[label="INSURANCE.CONNECTION.ACTIONS.CONNECT"]')
        .attributes('disabled')
    ).toBeDefined();
  });

  it('esconde os ramos que a corretora nao tem habilitados e conta quantos ficaram de fora', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();

    // `ready` traz auto (habilitado) e vida (nao habilitado)
    expect(wrapper.text()).toContain(
      'INSURANCE.CAPABILITIES.INSURERS_OF_TOTAL'
    );
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.HIDDEN_PRODUCTS');
    // Só o produto habilitado vira linha. As camadas viraram <details> e não entram na conta de
    // <li> desta seção — por isso a asserção continua valendo 1.
    expect(wrapper.findAll('li')).toHaveLength(1);
  });

  // O VEREDITO. Antes o topo dizia só "Conectado", e conectado não é a pergunta do corretor.
  it('responde quantos produtos dao para cotar, antes de qualquer detalhe', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();
    // `ready` tem um produto habilitado (auto) e um não habilitado (vida).
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.VERDICT.READY_ONE');
  });

  // Estes quatro nasceram de uma prova de mutação que saiu VERDE com o código removido: legenda,
  // rodapé, código do ramo e ordenação estavam na tela e não estavam em teste nenhum. Item que só
  // o olho humano defende volta a sumir na próxima refatoração.
  it('mostra legenda das cores e o rodape que explica produto ausente', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.LEGEND_QUOTING');
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.LEGEND_PENDING');
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.FOOTER');
  });

  // O código do ramo é o que o corretor lê ao telefone com o suporte da AGGER.
  it('mostra o codigo do ramo ao lado do produto', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('31');
  });

  // Mais seguradoras primeiro. A ordem crua do adapter é por código de ramo, que não diz nada a
  // quem lê — e "2" viria antes de "31".
  it('lista os produtos com mais seguradoras primeiro', async () => {
    const trio = {
      ...ready,
      capabilities: {
        products: [
          {
            ...ready.capabilities.products[0],
            product: 'bike',
            platformRef: '711',
            insurers: [
              {
                code: '1',
                name: 'Porto',
                enabled: true,
                integrationStatus: 'ready',
              },
            ],
          },
          {
            ...ready.capabilities.products[0],
            product: 'residencial',
            platformRef: '2',
            insurers: [
              {
                code: '1',
                name: 'Porto',
                enabled: true,
                integrationStatus: 'ready',
              },
              {
                code: '2',
                name: 'Zurich',
                enabled: true,
                integrationStatus: 'ready',
              },
              {
                code: '3',
                name: 'HDI',
                enabled: true,
                integrationStatus: 'ready',
              },
            ],
          },
          {
            ...ready.capabilities.products[0],
            product: 'celular',
            platformRef: '100',
            insurers: [
              {
                code: '1',
                name: 'Porto',
                enabled: true,
                integrationStatus: 'ready',
              },
              {
                code: '2',
                name: 'Zurich',
                enabled: true,
                integrationStatus: 'ready',
              },
            ],
          },
        ],
      },
    };
    api.getConnection.mockResolvedValue({ data: { payload: trio } });
    const wrapper = await mountTab();
    const texto = wrapper.text();
    expect(texto.indexOf('residencial')).toBeLessThan(texto.indexOf('celular'));
    expect(texto.indexOf('celular')).toBeLessThan(texto.indexOf('bike'));
  });

  // O teste de pluralização MUDOU DE ARQUIVO, e o motivo importa: aqui o i18n roda com
  // `messages: {}`, `t()` devolve a chave crua, e um `not.toContain('1 seguradoras')` passa sempre
  // — sem nunca renderizar a frase que deveria julgar. Um QA independente pegou exatamente isso:
  // o teste existia, estava verde, e a tela escrevia "0 de 1 seguradoras" em produção.
  //
  // Todo exemplo sobre TEXTO QUE O CORRETOR LÊ vive em `InsuranceConnectionsTab.copy.spec.js`,
  // que carrega as mensagens de verdade com `withFullI18n`.

  // Conexão sem produto nenhum não pode dizer "pronta para cotar 0 produtos": isso lê como se
  // estivesse tudo bem e o número fosse detalhe.
  it('sem produto habilitado, o veredito diz que nao esta cotando', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: { ...ready, capabilities: { products: [] } },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.VERDICT.NOT_READY');
    expect(wrapper.text()).not.toContain('INSURANCE.CONNECTION.VERDICT.READY');
  });

  // A CAMADA DE CREDENCIAIS SABIA E DIZIA "não verificado". O veredito vem do scan, e carimbado
  // com a data DELE — usar a do healthcheck faria a tela afirmar que verificou agora o que
  // verificou antes.
  it('a camada de credenciais responde pelo scan, e nomeia quem recusou', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          layers: { runtime: 'ok', insurer_auth: 'unknown' },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH_FAILED'
    );
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.LAYERS.FROM_SCAN');
  });

  // Sem scan não há o que derivar, e a camada tem de continuar dizendo "não sei" — o critério 1.2
  // existe para não confundir "não verificado" com "verificado e passou".
  it('sem scan, a camada de credenciais continua nao verificada', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          last_capability_scan_at: null,
          layers: { runtime: 'ok', insurer_auth: 'unknown' },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).not.toContain(
      'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH_FAILED'
    );
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.LAYERS.STATE.UNKNOWN'
    );
  });

  it('disconnect returns to not_configured', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: ready } });
    api.removeConnection.mockResolvedValue({ data: { payload: blank } });
    const wrapper = await mountTab();
    await wrapper
      .find('button[label="INSURANCE.CONNECTION.ACTIONS.DISCONNECT"]')
      .trigger('click');
    await flushPromises();
    expect(api.removeConnection).toHaveBeenCalledTimes(1);
    expect(wrapper.find('#insurance-agger-username').exists()).toBe(true);
  });

  // O CASO DE 05/09: sessão derrubada por login no navegador. Mesmo 403, mesma tela, causa oposta.
  it('não pede senha quando o que caiu foi a sessão, e não a credencial (1.1)', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...blank,
          status: 'degraded',
          failure: { cause: 'session_lost', actor: 'nobody', retryable: true },
          username_hint: 'x***@y.com',
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.FAILURES.SESSION_LOST'
    );
    expect(wrapper.text()).not.toContain(
      'INSURANCE.CONNECTION.FAILURES.CREDENTIAL_REJECTED'
    );
  });

  it('portal fora e integração desatualizada têm mensagens distintas entre si (1.1)', async () => {
    const textoPara = async (status, cause, actor) => {
      api.getConnection.mockResolvedValue({
        data: {
          payload: {
            ...blank,
            status,
            failure: { cause, actor },
            username_hint: 'x***@y.com',
          },
        },
      });
      return (await mountTab()).text();
    };

    const foraDoAr = await textoPara('offline', 'portal_unavailable', 'nobody');
    const desatualizada = await textoPara(
      'degraded',
      'integration_outdated',
      'autonomia'
    );

    expect(foraDoAr).toContain(
      'INSURANCE.CONNECTION.FAILURES.PORTAL_UNAVAILABLE'
    );
    expect(desatualizada).toContain(
      'INSURANCE.CONNECTION.FAILURES.INTEGRATION_OUTDATED'
    );
    expect(foraDoAr).not.toContain(
      'INSURANCE.CONNECTION.FAILURES.INTEGRATION_OUTDATED'
    );
  });

  // CRITÉRIO 1.2 — o que ninguém olhou aparece como não verificado, e não como vazio nem como ok.
  it('mostra as cinco camadas, com as não verificadas ditas por extenso', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          layers: {
            runtime: 'ok',
            platform_auth: 'ok',
            insurer_auth: 'unknown',
            product_support: 'unknown',
            risk: 'unknown',
          },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.LAYERS.INSURER_AUTH'
    );
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.LAYERS.RISK');
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.LAYERS.STATE.UNKNOWN'
    );
  });

  // CRITÉRIO 1.6 — instante absoluto e o que foi feito, nunca "há 3 minutos".
  it('diz quando verificou e com qual evidência', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          evidence: {
            check: 'session_probe',
            at: '2026-09-05T17:02:00.000Z',
            outcome: 'ok',
            detail: 'GET /cfg/corretora',
          },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.VERIFIED_AT');
  });

  // CRITÉRIO 4.5 — credencial de seguradora aparece na tela de Conexões, e só nela.
  it('mostra as seguradoras que recusaram a credencial da corretora', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          insurers_pending_auth: {
            codes: ['5', '9'],
            names: ['Allianz', 'Icatu'],
            observed_at: '2026-09-05T17:02:00.000Z',
          },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.INSURERS_PENDING.TITLE'
    );
    expect(wrapper.text()).toContain('Allianz, Icatu');
  });

  // CRITÉRIO 1.5 — decisão do Rodrigo: avisar, não bloquear. O caso real: a conta da SENA ligada no
  // Hub2You e na Autonomia ao mesmo tempo faz cotação de teste e cotação de cliente aparecerem
  // misturadas no portal da corretora, sem como distinguir.
  it('avisa quando a conta AGGER já estava em uso, e não bloqueia nada', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          account_already_active: {
            observed_at: '2026-09-06T14:05:00.000Z',
            session_started_at: '2026-09-06T14:02:00.000Z',
          },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.ALREADY_ACTIVE');
    // Avisar não é impedir: os botões seguem disponíveis.
    expect(
      wrapper
        .find('button[label="INSURANCE.CONNECTION.ACTIONS.RECONNECT"]')
        .attributes('disabled')
    ).toBeUndefined();
  });

  it('conta livre não gera aviso nenhum', async () => {
    api.getConnection.mockResolvedValue({ data: { payload: { ...ready } } });
    const wrapper = await mountTab();
    expect(wrapper.text()).not.toContain('INSURANCE.CONNECTION.ALREADY_ACTIVE');
  });

  // O NOME DO PORTAL VENCE O NOSSO MAPA. O ramo 46 é o caso real: o adapter manda
  // `label: 'Aluguel'` porque é assim que o AGGER o chama, e o nosso slug diz
  // `fianca_locaticia` — que é OUTRO produto no portal (id 23). Sem isto, o corretor lê na
  // tela um produto diferente do que vai cotar, e o slug não pode mudar porque já viajou
  // para o banco.
  it('mostra o rótulo que o portal usa, e não a tradução do slug', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...ready,
          capabilities: {
            products: [
              {
                product: 'fianca_locaticia',
                label: 'Aluguel',
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
              },
            ],
          },
        },
      },
    });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain('Aluguel');
    expect(wrapper.text()).not.toContain('INSURANCE.PRODUCTS.FIANCA_LOCATICIA');
  });
});
