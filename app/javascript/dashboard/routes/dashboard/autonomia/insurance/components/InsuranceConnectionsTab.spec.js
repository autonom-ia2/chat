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
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.INSURERS_COUNT');
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.PENDING_AUTH');
    expect(wrapper.find('#insurance-agger-password').exists()).toBe(false);
  });

  it('shows auth_required with the last error and lets the user reconnect', async () => {
    api.getConnection.mockResolvedValue({
      data: {
        payload: {
          ...blank,
          status: 'auth_required',
          last_error: 'auth_required: invalid credentials',
          username_hint: 'x***@y.com',
        },
      },
    });
    api.reconnect.mockResolvedValue({ data: { payload: ready } });
    const wrapper = await mountTab();
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.AUTH_REQUIRED'
    );
    expect(wrapper.text()).toContain('auth_required: invalid credentials');

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
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.INSURERS_COUNT');
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.HIDDEN_PRODUCTS');
    expect(wrapper.findAll('li')).toHaveLength(1);
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
});
