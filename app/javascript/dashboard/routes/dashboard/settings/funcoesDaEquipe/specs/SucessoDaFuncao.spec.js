import { mount } from '@vue/test-utils';
import SucessoDaFuncao from '../guiada/SucessoDaFuncao.vue';
import { global } from './montar';

// #2308, especificação 5.B5. Rodada 5: a página leva o foco para o h1 ao trocar de etapa, e um role=status preenchido
// na mesma tarefa não era anunciado. O "criada" mora no próprio alvo do foco: o h1 o descreve (aria-describedby), e o
// leitor de tela diz os dois ao focar.
describe('SucessoDaFuncao', () => {
  it('o h1 que recebe o foco é descrito por "Função … criada."', () => {
    const wrapper = mount(SucessoDaFuncao, {
      attachTo: document.body,
      props: { nome: 'Atendente', podeEscolherPessoas: true },
      global: global(),
    });
    const titulo = wrapper.find('h1');
    expect(titulo.text()).toBe('Quem vai ser Atendente?');
    const descricao = document.getElementById(
      titulo.attributes('aria-describedby')
    );
    expect(descricao?.textContent.trim()).toBe('Função Atendente criada.');
    expect(wrapper.find('[role="status"]').exists()).toBe(false);
    wrapper.unmount();
  });

  it('sem poder pôr pessoas, o próprio h1 diz que foi criada', () => {
    const wrapper = mount(SucessoDaFuncao, {
      props: { nome: 'Atendente', podeEscolherPessoas: false },
      global: global(),
    });
    expect(wrapper.find('h1').text()).toBe('Função Atendente criada.');
    wrapper.unmount();
  });
});
