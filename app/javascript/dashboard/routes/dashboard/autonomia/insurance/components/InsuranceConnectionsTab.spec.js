import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { mount } from '@vue/test-utils';
import InsuranceConnectionsTab from './InsuranceConnectionsTab.vue';

// O componente é contract-first: sem API. O que vale testar é o contrato visível —
// formulário só em not_configured, senha nunca sobrevive ao submit, estados transitórios
// até READY, e a lista de produtos aparecendo só depois de conectado.
describe('InsuranceConnectionsTab', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  const mountTab = () => mount(InsuranceConnectionsTab);

  it('starts not configured with the credentials form and no capabilities', () => {
    const wrapper = mountTab();

    expect(wrapper.find('#insurance-agger-username').exists()).toBe(true);
    expect(wrapper.find('#insurance-agger-password').exists()).toBe(true);
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.NOT_CONFIGURED'
    );
    expect(wrapper.text()).not.toContain('INSURANCE.CAPABILITIES.TITLE');
  });

  it('refuses to connect without username and password', async () => {
    const wrapper = mountTab();

    await wrapper.find('button').trigger('click');

    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.FORM.REQUIRED');
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.NOT_CONFIGURED'
    );
  });

  it('walks provisioning → authenticating → discovering → ready and lists products', async () => {
    const wrapper = mountTab();

    await wrapper
      .find('#insurance-agger-username')
      .setValue('corretora@exemplo.com.br');
    await wrapper.find('#insurance-agger-password').setValue('segredo');
    await wrapper.find('button').trigger('click');

    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.PROVISIONING'
    );
    // formulário some e a senha não fica em lugar nenhum do DOM
    expect(wrapper.find('#insurance-agger-password').exists()).toBe(false);
    expect(wrapper.html()).not.toContain('segredo');
    // login exibido só mascarado
    expect(wrapper.text()).toContain('co*******@exemplo.com.br');
    expect(wrapper.text()).not.toContain('corretora@exemplo.com.br');

    await vi.advanceTimersByTimeAsync(700);
    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.AUTHENTICATING'
    );

    await vi.advanceTimersByTimeAsync(700);
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.STATES.DISCOVERING');

    await vi.advanceTimersByTimeAsync(700);
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.STATES.READY');
    expect(wrapper.text()).toContain('INSURANCE.CAPABILITIES.TITLE');
    expect(wrapper.text()).toContain('INSURANCE.PRODUCTS.AUTO');
    expect(wrapper.text()).toContain('INSURANCE.PRODUCTS.RESIDENCIAL');
  });

  it('disconnect returns to not_configured and drops capabilities', async () => {
    const wrapper = mountTab();

    await wrapper
      .find('#insurance-agger-username')
      .setValue('corretora@exemplo.com.br');
    await wrapper.find('#insurance-agger-password').setValue('segredo');
    await wrapper.find('button').trigger('click');
    await vi.advanceTimersByTimeAsync(2100);
    expect(wrapper.text()).toContain('INSURANCE.CONNECTION.STATES.READY');

    const disconnect = wrapper.find(
      'button[label="INSURANCE.CONNECTION.ACTIONS.DISCONNECT"]'
    );
    await disconnect.trigger('click');

    expect(wrapper.text()).toContain(
      'INSURANCE.CONNECTION.STATES.NOT_CONFIGURED'
    );
    expect(wrapper.text()).not.toContain('INSURANCE.CAPABILITIES.TITLE');
    expect(wrapper.find('#insurance-agger-username').exists()).toBe(true);
  });
});
