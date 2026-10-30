import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/seusPosts.json';
import ComentarioLinha from '../components/ComentarioLinha.vue';
import { comentarioParaTela } from '../seusPostsDados';

// Seus posts F2 (#2305): uma linha de comentário. Os botões seguem o `pode` do servidor; o texto escrito só some
// quando quem chama confirma o sucesso. Dados sintéticos.
const comentario = (extra = {}) =>
  comentarioParaTela({
    id: '18000000000000001',
    text: 'Tem no tamanho M?',
    created_time: new Date().toISOString(),
    author: { username: 'cliente.exemplo' },
    replies: [],
    can_reply: true,
    can_hide: true,
    can_delete: true,
    can_reply_private: true,
    ...extra,
  });

const montar = (dados, props = {}, noDocumento = false) =>
  mount(ComentarioLinha, {
    props: { comentario: dados, ...props },
    attachTo: noDocumento ? document.body : undefined,
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
      stubs: {
        RouterLink: { props: ['to'], template: '<a :href="to"><slot /></a>' },
        DropdownMenu: {
          props: ['menuItems'],
          emits: ['action'],
          template:
            '<div><button v-for="item in menuItems" :key="item.action" :data-item="item.action" @click="$emit(\'action\', item)">{{ item.label }}</button></div>',
        },
      },
    },
  });

const abrirMais = async (wrapper, acao) => {
  await wrapper.find('[data-seus-posts-mais]').trigger('click');
  await wrapper.find(`[data-item="${acao}"]`).trigger('click');
};

describe('ComentarioLinha', () => {
  it('esperando você: Responder em destaque e o resto no Mais', async () => {
    const wrapper = montar(comentario());

    expect(wrapper.attributes('data-estado')).toBe('esperando');
    expect(wrapper.find('[data-seus-posts-acao]').text()).toBe('Responder');
    await wrapper.find('[data-seus-posts-mais]').trigger('click');
    expect(wrapper.findAll('[data-item]').map(b => b.text())).toEqual([
      'Mandar no privado',
      'Esconder',
      'Apagar',
    ]);
  });

  it('quem só vê não recebe nenhum botão', () => {
    const wrapper = montar(
      comentario({
        can_reply: false,
        can_hide: false,
        can_delete: false,
        can_reply_private: false,
      })
    );

    expect(wrapper.find('[data-seus-posts-acao]').exists()).toBe(false);
    expect(wrapper.find('[data-seus-posts-mais]').exists()).toBe(false);
  });

  it('responder manda o texto e só limpa quando quem chama confirma', async () => {
    const wrapper = montar(comentario());

    await wrapper.find('[data-seus-posts-acao]').trigger('click');
    await wrapper.find('textarea').setValue('  Tem sim!  ');
    await wrapper.find('form').trigger('submit');

    const [texto, pronto] = wrapper.emitted('responder')[0];
    expect(texto).toBe('Tem sim!');
    expect(wrapper.find('textarea').element.value).toBe('  Tem sim!  ');
    pronto();
    await wrapper.vm.$nextTick();
    expect(wrapper.find('textarea').exists()).toBe(false);
  });

  it('o privado sai pelo evento privado, com o aviso das regras da Meta', async () => {
    const wrapper = montar(comentario());

    await abrirMais(wrapper, 'privado');
    expect(
      wrapper.find('[data-seus-posts-escrever="privado"]').text()
    ).toContain('até 7 dias');
    await wrapper.find('textarea').setValue('Te chamei no direct');
    await wrapper.find('form').trigger('submit');

    expect(wrapper.emitted('privado')[0][0]).toBe('Te chamei no direct');
    expect(wrapper.emitted('responder')).toBeUndefined();
  });

  it('abrir leva o foco ao campo; cancelar volta aos botões da linha', async () => {
    const wrapper = montar(comentario(), {}, true);

    await wrapper.find('[data-seus-posts-acao]').trigger('click');
    await wrapper.vm.$nextTick();
    expect(document.activeElement).toBe(wrapper.find('textarea').element);
    await wrapper.find('button[type="button"]').trigger('click');
    await wrapper.vm.$nextTick();
    expect(document.activeElement).toBe(
      wrapper.find('[data-seus-posts-acao]').element
    );
    wrapper.unmount();
  });

  it('não envia texto vazio', async () => {
    const wrapper = montar(comentario());

    await wrapper.find('[data-seus-posts-acao]').trigger('click');

    expect(
      wrapper.find('[data-seus-posts-enviar]').attributes('disabled')
    ).toBeDefined();
  });

  it('apagar pede confirmação antes', async () => {
    const wrapper = montar(comentario());

    await abrirMais(wrapper, 'apagar');
    expect(wrapper.emitted('apagar')).toBeUndefined();
    expect(wrapper.find('[data-seus-posts-confirmar-apagar]').text()).toContain(
      '@cliente.exemplo'
    );
    await wrapper.find('[data-seus-posts-apagar]').trigger('click');

    expect(wrapper.emitted('apagar')).toHaveLength(1);
  });

  it('escondido: Mostrar de novo em destaque, sem responder nem privado', async () => {
    const wrapper = montar(comentario({ hidden: true }));

    expect(wrapper.attributes('data-estado')).toBe('escondido');
    await wrapper.find('[data-seus-posts-acao]').trigger('click');
    expect(wrapper.emitted('esconder')[0]).toEqual([false]);
    await wrapper.find('[data-seus-posts-mais]').trigger('click');
    expect(
      wrapper.findAll('[data-item]').map(b => b.attributes('data-item'))
    ).toEqual(['apagar']);
  });

  it('privado mandado mostra a conversa e o "Não foi enviado" quando dá para liberar', async () => {
    const wrapper = montar(
      comentario({
        can_reply_private: false,
        private_reply: {
          sent_at: new Date().toISOString(),
          confirmed: false,
          conversation_path: '/app/accounts/1/conversations/9',
          can_release: true,
        },
      })
    );

    expect(wrapper.attributes('data-estado')).toBe('privado');
    expect(wrapper.find('[data-seus-posts-ver-conversa]').exists()).toBe(true);
    await wrapper.find('[data-seus-posts-liberar-privado]').trigger('click');
    expect(wrapper.emitted('liberar')).toHaveLength(1);
  });

  it('a resposta da própria conta marca o comentário como respondido', () => {
    const wrapper = montar(
      comentario({
        replies: [
          {
            id: 'r1',
            text: 'Tem sim!',
            author: { name: 'Loja', is_page: true },
          },
        ],
      })
    );

    expect(wrapper.attributes('data-estado')).toBe('respondido');
    expect(wrapper.find('[data-seus-posts-resposta-do-dono]').exists()).toBe(
      true
    );
  });

  it('ocupado: os botões esperam', () => {
    const wrapper = montar(comentario(), { ocupado: true });

    expect(
      wrapper.find('[data-seus-posts-acao]').attributes('disabled')
    ).toBeDefined();
  });
});
