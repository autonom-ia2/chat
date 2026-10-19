import { mount } from '@vue/test-utils';
import NovaConversaParaQuem from '../NovaConversaParaQuem.vue';
import NovaConversaContatoNovo from '../NovaConversaContatoNovo.vue';

// #1809 (decisão do Rodrigo, 18/10): o cartão "Criar contato" com nome, e-mail e
// telefone só com a chave conversa_email_nova; sem ela, o "Criar contato" de antes.
const montar = contatoNovoCompleto =>
  mount(NovaConversaParaQuem, {
    props: { termo: 'marina@exemplo.com', resultados: [], contatoNovoCompleto },
    global: {
      mocks: { $t: (chave, valores) => `${chave}${valores?.valor || ''}` },
      stubs: { NovaConversaContatoNovo: true },
    },
  });

describe('NovaConversaParaQuem — criar contato', () => {
  it('com a chave: o cartão com nome, e-mail e telefone', () => {
    const tela = montar(true);

    expect(tela.findComponent(NovaConversaContatoNovo).exists()).toBe(true);
    expect(tela.text()).not.toContain('NOVA_CONVERSA.PARA_QUEM.CRIAR');
  });

  it('sem a chave: o botão "Criar contato <valor>" de antes, que cria pelo termo', async () => {
    const tela = montar(false);

    expect(tela.findComponent(NovaConversaContatoNovo).exists()).toBe(false);
    const botao = tela.find('button');
    expect(botao.text()).toContain(
      'NOVA_CONVERSA.PARA_QUEM.CRIARmarina@exemplo.com'
    );
    await botao.trigger('click');
    expect(tela.emitted('criar')).toEqual([[]]);
  });
});
