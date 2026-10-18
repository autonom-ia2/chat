import { nextTick, ref } from 'vue';
import { mount } from '@vue/test-utils';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: chave => chave, locale: ref('pt_BR') }),
}));
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
  it('o que foi digitado na busca vai para o campo certo', async () => {
    const porEmail = montar({ termo: 'marina@exemplo.com.br' });
    const porTelefone = montar({ termo: '(11) 98765-0001' });
    const porNome = montar({ termo: 'Marina Costa' });
    await nextTick();
    expect(porEmail.find('input[data-campo-email]').element.value).toBe(
      'marina@exemplo.com.br'
    );
    expect(
      porTelefone.find('[data-campo-telefone] input[inputmode=tel]').element
        .value
    ).toBe('(11) 98765-0001');
    expect(porNome.find('input[data-campo-nome]').element.value).toBe(
      'Marina Costa'
    );
  });

  it('sem nome não cria', async () => {
    const wrapper = montar({ termo: 'marina@exemplo.com.br' });
    expect(await enviar(wrapper)).toBeUndefined();
    expect(wrapper.text()).toContain('FALTA_NOME');
  });

  it('vindo do e-mail, exige o e-mail', async () => {
    const wrapper = montar({ termo: 'Marina Costa', exigeEmail: true });
    await wrapper
      .find('[data-campo-telefone] input[inputmode=tel]')
      .setValue('11987650001');
    expect(await enviar(wrapper)).toBeUndefined();
    expect(wrapper.text()).toContain('FALTA_EMAIL');
  });

  it('cria com nome, e-mail e telefone com DDD do Brasil', async () => {
    const wrapper = montar({
      termo: 'marina@exemplo.com.br',
      exigeEmail: true,
    });
    await wrapper.find('input[data-campo-nome]').setValue('Marina Costa');
    await wrapper
      .find('[data-campo-telefone] input[inputmode=tel]')
      .setValue('(11) 98765-0001');
    expect(await enviar(wrapper)).toEqual({
      nome: 'Marina Costa',
      email: 'marina@exemplo.com.br',
      telefone: '+5511987650001',
    });
  });

  it('telefone pela metade avisa, em vez de sumir calado', async () => {
    const wrapper = montar({ termo: 'marina@exemplo.com.br' });
    await wrapper.find('input[data-campo-nome]').setValue('Marina');
    await wrapper
      .find('[data-campo-telefone] input[inputmode=tel]')
      .setValue('11987');
    expect(await enviar(wrapper)).toBeUndefined();
    expect(wrapper.text()).toContain('TELEFONE_INVALIDO');
  });

  it('telefone opcional: sem ele, cria só com nome e e-mail', async () => {
    const wrapper = montar({ termo: 'marina@exemplo.com.br' });
    await wrapper.find('input[data-campo-nome]').setValue('Marina');
    expect(await enviar(wrapper)).toEqual({
      nome: 'Marina',
      email: 'marina@exemplo.com.br',
      telefone: '',
    });
  });
});
