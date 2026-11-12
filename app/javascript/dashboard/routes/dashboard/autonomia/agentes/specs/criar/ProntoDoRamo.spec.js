import { h } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ProntoDoRamo from '../../components/criar/ProntoDoRamo.vue';

// #2881 — no Confira de um agente pronto por ramo: o que ele já traz, em linhas curtas, cada uma abrindo a gaveta com
// a lista inteira. As listas são as do servidor; a mudança sai com o nome da lista e a lista inteira nova. Cópia real.
withFullI18n('pt_BR');

const PERGUNTAS = [
  { id: 'p1', texto: 'Qual o CNPJ da empresa?', tirada: false },
  { id: 'p2', texto: 'Qual o valor da garantia?', tirada: true },
  { id: 'p3', texto: 'Quem cuida disso?', tirada: false },
];
const DOCUMENTOS = [{ id: 'd1', texto: 'Edital ou contrato.', tirada: false }];

const montadas = [];
const montar = (props = {}) => {
  const wrapper = mount(ProntoDoRamo, {
    props: {
      nome: 'Bia',
      perguntas: PERGUNTAS,
      documentos: DOCUMENTOS,
      ferramentas: 4,
      podeMudar: true,
      ...props,
    },
    slots: {
      ferramentas: () => h('p', { 'data-do-slot': '' }, 'ferramentas aqui'),
    },
    attachTo: document.body,
  });
  montadas.push(wrapper);
  return wrapper;
};
const linha = (wrapper, chave) => wrapper.get(`[data-linha="${chave}"]`);
const gaveta = () => document.body.querySelector('[role="dialog"]');

afterEach(() => {
  montadas.splice(0).forEach(wrapper => wrapper.unmount());
  document.body.innerHTML = '';
});

describe('ProntoDoRamo', () => {
  it('says in short lines what the agent brings, counting only what the owner kept', () => {
    const wrapper = montar();

    expect(wrapper.get('h3').text()).toBe('O que Bia já traz');
    expect(linha(wrapper, 'perguntas').text()).toContain(
      'Perguntas ao cliente, uma por vez: 2'
    );
    expect(linha(wrapper, 'documentos').text()).toContain(
      'Documentos que pede: 1'
    );
    expect(linha(wrapper, 'ferramentas').text()).toContain(
      'Ferramentas que já vêm: 4'
    );
    expect(
      linha(wrapper, 'perguntas').get('button').attributes('aria-label')
    ).toBe('Ver o que Bia pergunta');
  });

  it('has no tools line when the account has no tools to show', () => {
    const wrapper = montar({ ferramentas: null });

    expect(wrapper.find('[data-linha="ferramentas"]').exists()).toBe(false);
    expect(wrapper.findAll('[data-linha]')).toHaveLength(2);
  });

  it('"See" opens the drawer with the whole list, and a change leaves with the name of the list', async () => {
    const wrapper = montar();

    await linha(wrapper, 'perguntas').get('button').trigger('click');
    expect(gaveta().textContent).toContain('O que Bia pergunta');
    expect(gaveta().querySelectorAll('[data-item]')).toHaveLength(3);

    gaveta().querySelector('[data-item="p1"] [data-tirar-item]').click();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('mudar')).toEqual([
      [
        {
          lista: 'perguntas',
          itens: [
            { ...PERGUNTAS[0], tirada: true },
            PERGUNTAS[1],
            PERGUNTAS[2],
          ],
        },
      ],
    ]);
  });

  it('the documents drawer changes the documents list', async () => {
    const wrapper = montar();

    await linha(wrapper, 'documentos').get('button').trigger('click');
    expect(gaveta().textContent).toContain('Documentos que Bia pede');
    gaveta().querySelector('[data-item="d1"] [data-tirar-item]').click();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('mudar')[0][0]).toEqual({
      lista: 'documentos',
      itens: [{ ...DOCUMENTOS[0], tirada: true }],
    });
  });

  it('shows what the server keeps: the list in the drawer follows the new props', async () => {
    const wrapper = montar();
    await linha(wrapper, 'perguntas').get('button').trigger('click');

    await wrapper.setProps({
      perguntas: [
        ...PERGUNTAS,
        { id: 'p4', texto: 'Já tem seguro?', tirada: false },
      ],
    });

    expect(gaveta().querySelectorAll('[data-item]')).toHaveLength(4);
    expect(linha(wrapper, 'perguntas').text()).toContain(': 3');
  });

  it('only the list being saved waits', async () => {
    const wrapper = montar({ gravando: { documentos: true } });

    await linha(wrapper, 'perguntas').get('button').trigger('click');
    expect(
      gaveta().querySelector('[data-tirar-item]').getAttribute('aria-disabled')
    ).toBeNull();
    gaveta().querySelector('[data-fechar]').click();
    await wrapper.vm.$nextTick();

    await linha(wrapper, 'documentos').get('button').trigger('click');
    expect(
      gaveta().querySelector('[data-tirar-item]').getAttribute('aria-disabled')
    ).toBe('true');
  });

  it('the tools drawer shows what the page puts in the slot', async () => {
    const wrapper = montar();

    await linha(wrapper, 'ferramentas').get('button').trigger('click');

    expect(gaveta().textContent).toContain('Ferramentas de Bia');
    expect(gaveta().querySelector('[data-do-slot]')).not.toBeNull();
  });
});
