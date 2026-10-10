import { mount } from '@vue/test-utils';
import MaterialDaConversa from '../../components/criar/MaterialDaConversa.vue';

const material = extra => ({
  id: 1,
  nome: 'Tabela de preços.pdf',
  tipo: 'arquivo',
  ...extra,
});
const montar = (estado, extra) =>
  mount(MaterialDaConversa, { props: { material: material(extra), estado } });

describe('MaterialDaConversa', () => {
  it('hides a short extension and says the state in words', () => {
    const wrapper = montar('lendo');
    expect(wrapper.text()).toContain('Tabela de preços');
    expect(wrapper.text()).not.toContain('.pdf');
    expect(wrapper.text()).toContain('AGENTS.JORNADA.CRIAR.MATERIAL.LENDO');
  });

  it.each([
    ['pronto', 'AGENTS.JORNADA.CRIAR.MATERIAL.PRONTO'],
    ['fila', 'AGENTS.JORNADA.CRIAR.MATERIAL.FILA'],
    ['grande', 'AGENTS.JORNADA.CRIAR.MATERIAL.GRANDE'],
    ['atencao', 'AGENTS.JORNADA.CRIAR.MATERIAL.ATENCAO_TEXTO'],
  ])('shows the %s state', (estado, texto) => {
    expect(montar(estado).text()).toContain(texto);
  });

  it('offers "send another" and "remove" only when it could not be read', async () => {
    expect(montar('pronto').find('[data-tirar]').exists()).toBe(false);
    const wrapper = montar('atencao');
    await wrapper.get('[data-mandar-outro]').trigger('click');
    await wrapper.get('[data-tirar]').trigger('click');
    expect(wrapper.emitted('mandarOutro')).toHaveLength(1);
    expect(wrapper.emitted('tirar')).toHaveLength(1);
    expect(
      wrapper.findAll('button').every(b => b.classes().includes('min-h-11'))
    ).toBe(true);
  });

  it('a file too big can only be removed', () => {
    const wrapper = montar('grande');
    expect(wrapper.find('[data-mandar-outro]').exists()).toBe(false);
    expect(wrapper.find('[data-tirar]').exists()).toBe(true);
  });

  it('keeps a site address whole', () => {
    expect(montar('lendo', { nome: 'www.loja.com.br' }).text()).toContain(
      'www.loja.com.br'
    );
  });
});
