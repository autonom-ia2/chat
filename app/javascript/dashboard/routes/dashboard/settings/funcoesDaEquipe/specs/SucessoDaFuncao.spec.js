import { flushPromises, mount } from '@vue/test-utils';
import SucessoDaFuncao from '../guiada/SucessoDaFuncao.vue';
import { global } from './montar';

// #2308, especificação 5.B5. Rodada 4: um role=status que já nasce com o texto não é anunciado; o "criada" entra
// depois de montar, para o leitor de tela dizer, enquanto o foco vai para o h1.
describe('SucessoDaFuncao', () => {
  it('o status nasce vazio e recebe "criada" depois de montar', async () => {
    const wrapper = mount(SucessoDaFuncao, {
      props: { nome: 'Atendente', podeEscolherPessoas: true },
      global: global(),
    });
    const status = wrapper.find('[role="status"]');
    expect(status.exists()).toBe(true);
    expect(status.text()).toBe('');

    await flushPromises();
    expect(wrapper.find('[role="status"]').text()).toContain('Atendente');
  });
});
