import { h } from 'vue';
import { mount } from '@vue/test-utils';
import { withFullI18n } from 'test-i18n';
import ProntoDoRamo from '../../components/criar/ProntoDoRamo.vue';

// A gaveta abre num TeleportWithDirection, que lê a direção do texto na store.
vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => ({ getters: {}, dispatch: vi.fn() }),
    useMapGetter: () => computed(() => false),
  };
});

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

  it('a change typed in a field carries the "saved" notice, and the field closes only when it is called', async () => {
    const wrapper = montar();
    await linha(wrapper, 'perguntas').get('button').trigger('click');

    gaveta().querySelector('[data-item="p1"] [data-editar-item]').click();
    await wrapper.vm.$nextTick();
    const campo = gaveta().querySelector('[data-editando] textarea');
    campo.value = 'Qual o CNPJ de quem contrata?';
    campo.dispatchEvent(new Event('input'));
    await wrapper.vm.$nextTick();
    gaveta().querySelector('[data-salvar-item]').click();
    await wrapper.vm.$nextTick();

    const [{ lista, itens, aoGravar }] = wrapper.emitted('mudar')[0];
    expect(lista).toBe('perguntas');
    expect(itens).toEqual([
      { ...PERGUNTAS[0], texto: 'Qual o CNPJ de quem contrata?' },
      PERGUNTAS[1],
      PERGUNTAS[2],
    ]);
    expect(gaveta().querySelector('[data-editando]')).not.toBeNull();
    aoGravar();
    await wrapper.vm.$nextTick();
    expect(gaveta().querySelector('[data-editando]')).toBeNull();
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

  // #3020 — o modelo que traz as perguntas em blocos abre a gaveta de ligar e desligar; o resto segue igual.
  it('opens the questions in blocks when the model brings them in blocks, and a tap leaves with the whole list', async () => {
    const emBlocos = [
      { id: 'p1', texto: 'Qual o CEP?', tirada: false, bloco: 'Endereço' },
      { id: 'p2', texto: 'Tem complemento?', tirada: true, bloco: 'Endereço' },
    ];
    const wrapper = montar({ perguntas: emBlocos });

    expect(linha(wrapper, 'perguntas').text()).toContain(
      'Perguntas ao cliente, uma por vez: 1'
    );
    await linha(wrapper, 'perguntas').get('button').trigger('click');
    expect(gaveta().textContent).toContain(
      'Ligue só o que Bia deve perguntar.'
    );
    expect(gaveta().querySelector('[data-perguntas-em-blocos]')).not.toBeNull();
    expect(
      gaveta().querySelector('[data-itens-do-ramo] [data-item]')
    ).toBeNull();

    gaveta().querySelector('[data-pergunta="p2"]').click();
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('mudar')).toEqual([
      [
        {
          lista: 'perguntas',
          itens: [emBlocos[0], { ...emBlocos[1], tirada: false }],
          aoGravar: expect.any(Function),
        },
      ],
    ]);

    await wrapper.setProps({ perguntas: PERGUNTAS });
    expect(gaveta().querySelector('[data-perguntas-em-blocos]')).toBeNull();
    expect(gaveta().querySelectorAll('[data-item]')).toHaveLength(3);
  });
});
