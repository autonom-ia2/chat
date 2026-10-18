import { mount } from '@vue/test-utils';
import NovaConversaContatoNovo from '../NovaConversaContatoNovo.vue';

// #1809: contato novo na gaveta com nome (obrigatório), e-mail e telefone.
const montar = props =>
  mount(NovaConversaContatoNovo, {
    props,
    global: {
      mocks: { $t: chave => chave },
      stubs: { Button: { template: '<button type="submit">criar</button>' } },
    },
  });

const enviar = async wrapper => {
  await wrapper.find('form').trigger('submit');
  return wrapper.emitted('criar')?.[0]?.[0];
};

describe('NovaConversaContatoNovo', () => {
  it('o que foi digitado na busca vai para o campo certo', () => {
    expect(
      montar({ termo: 'marina@exemplo.com.br' }).find('[data-campo-email]')
        .element.value
    ).toBe('marina@exemplo.com.br');
    expect(
      montar({ termo: '(11) 98765-0001' }).find('[data-campo-telefone]').element
        .value
    ).toBe('(11) 98765-0001');
    expect(
      montar({ termo: 'Marina Costa' }).find('[data-campo-nome]').element.value
    ).toBe('Marina Costa');
  });

  it('sem nome não cria', async () => {
    const wrapper = montar({ termo: 'marina@exemplo.com.br' });
    expect(await enviar(wrapper)).toBeUndefined();
    expect(wrapper.find('[role=alert]').text()).toContain('FALTA_NOME');
  });

  it('vindo do e-mail, exige o e-mail', async () => {
    const wrapper = montar({ termo: 'Marina Costa', exigeEmail: true });
    await wrapper.find('[data-campo-telefone]').setValue('11987650001');
    expect(await enviar(wrapper)).toBeUndefined();
    expect(wrapper.find('[role=alert]').text()).toContain('FALTA_EMAIL');
  });

  it('cria com nome, e-mail e telefone com DDD do Brasil', async () => {
    const wrapper = montar({
      termo: 'marina@exemplo.com.br',
      exigeEmail: true,
    });
    await wrapper.find('[data-campo-nome]').setValue('Marina Costa');
    await wrapper.find('[data-campo-telefone]').setValue('(11) 98765-0001');
    expect(await enviar(wrapper)).toEqual({
      nome: 'Marina Costa',
      email: 'marina@exemplo.com.br',
      telefone: '+5511987650001',
    });
  });

  it('telefone opcional: sem ele, cria só com nome e e-mail', async () => {
    const wrapper = montar({ termo: 'marina@exemplo.com.br' });
    await wrapper.find('[data-campo-nome]').setValue('Marina');
    expect(await enviar(wrapper)).toEqual({
      nome: 'Marina',
      email: 'marina@exemplo.com.br',
      telefone: '',
    });
  });
});
