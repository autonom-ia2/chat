import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import VitrineJaVem from '../../vitrine/components/VitrineJaVem.vue';

// #2858 F3 — o Confira mostra antes de fazer: as prontas com que o agente nasce, cada uma com "Tirar". Lista vazia
// ("nenhuma combina") não mostra nada. Sem a chave das ferramentas, uma frase simples diz que o agente começa sem
// elas, sem esconder em silêncio. Cópia real em pt_BR.
withFullI18n('pt_BR');

const montadas = [];
const montar = props => {
  const wrapper = mount(VitrineJaVem, {
    props: { nome: 'Ana', ...props },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('VitrineJaVem', () => {
  it('lists each tool with what it does and an accessible "Remove"', async () => {
    const wrapper = montar({ ids: ['fipe', 'cep'] });

    expect(wrapper.text()).toContain('Ana já vem com estas ferramentas');
    expect(wrapper.find('[data-ja-vem-item="fipe"]').text()).toContain(
      'Valor do carro'
    );
    const tirar = wrapper.findAll('[data-ja-vem-tirar]');
    expect(tirar).toHaveLength(2);
    expect(tirar[0].attributes('aria-label')).toBe('Tirar Valor do carro');

    await tirar[0].trigger('click');
    expect(wrapper.emitted('tirar')).toEqual([['fipe']]);
  });

  it('"none fits": nothing on screen', () => {
    expect(montar({ ids: [] }).find('[data-ja-vem]').exists()).toBe(false);
  });

  it('without the tools key: one plain sentence, no list and no "Remove"', () => {
    const wrapper = montar({ ids: ['fipe', 'cep'], semPermissao: true });

    expect(wrapper.find('[data-ja-vem]').exists()).toBe(true);
    expect(wrapper.findAll('[data-ja-vem-tirar]')).toHaveLength(0);
    expect(wrapper.text()).toContain('Ana se daria bem com: Valor do carro');
    expect(wrapper.text()).toContain('o agente começa sem elas');
  });
});
