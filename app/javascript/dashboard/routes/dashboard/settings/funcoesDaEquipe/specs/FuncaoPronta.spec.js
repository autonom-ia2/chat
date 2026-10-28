import { mount } from '@vue/test-utils';
import { PRONTAS, cartaoPronto } from '../cartaoPronto';
import FuncaoPronta from '../guiada/FuncaoPronta.vue';
import { global } from './montar';
import { CARLA } from './quemMonta';

// #2308, especificação 5.B1 e 7.8: toque único e "Pôr uma pessoa nela" só com Pessoas e alcance.
const atendente = cartaoPronto(PRONTAS[0], CARLA);
const existente = { funcao: { id: 1, name: 'Atendente' }, pessoas: 3 };

const montar = props =>
  mount(FuncaoPronta, {
    props: { cartao: atendente, ...props },
    global: global(),
  });

describe('FuncaoPronta', () => {
  it('sem a função na conta, o cartão inteiro cria a pronta', async () => {
    const wrapper = montar();
    const principal = wrapper.find('[data-principal]');
    expect(principal.attributes('aria-label')).toBe('Criar Atendente');
    expect(principal.classes()).toContain('after:inset-0');
    expect(wrapper.find('footer').exists()).toBe(false);
    await principal.trigger('click');
    expect(wrapper.emitted('criar')).toHaveLength(1);
  });

  it('com Pessoas e alcance: "Pôr uma pessoa nela" e o link irmão', async () => {
    const wrapper = montar({ existente, podePorPessoa: true });
    expect(wrapper.text()).toContain('Você já tem esta função · 3 pessoas');
    expect(wrapper.find('[data-principal]').text()).toBe('Pôr uma pessoa nela');
    await wrapper.find('[data-principal]').trigger('click');
    expect(wrapper.emitted('porPessoa')).toHaveLength(1);
    await wrapper.find('[data-criar-a-partir]').trigger('click');
    expect(wrapper.emitted('criar')).toHaveLength(1);
  });

  it.each([
    ['ABOVE', 'Só o administrador põe pessoas nela.'],
    ['MINE', 'Ninguém muda a própria função.'],
  ])('com trava %s, "Pôr uma pessoa nela" some', (trava, texto) => {
    const wrapper = montar({ existente, travaDaPessoa: trava });
    expect(wrapper.text()).not.toContain('Pôr uma pessoa nela');
    expect(wrapper.find('[data-trava-pessoa]').text()).toBe(texto);
    expect(wrapper.find('[data-principal]').text()).toBe(
      'Criar outra a partir da pronta'
    );
    expect(wrapper.find('[data-criar-a-partir]').exists()).toBe(false);
  });

  it('as capacidades da pronta, com o ícone do tipo', () => {
    const wrapper = montar();
    const itens = wrapper.findAll('[data-tipo]');
    expect(itens.map(item => item.text())).toEqual([
      'Atende as próprias conversas',
      'Cria e move as vendas',
      'Só olha os contatos',
    ]);
    expect(itens[2].html()).toContain('i-lucide-eye');
  });
});
