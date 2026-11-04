import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'dashboard/i18n/locale/pt_BR/conversaCanal.json';
import api from 'dashboard/api/comentarioDaConversa';
import { useAlert } from 'dashboard/composables';
import ComentarioNaConversa from '../ComentarioNaConversa.vue';

// Comentários na caixa (#2215): o cartão do comentário no topo da conversa. Os botões seguem o `pode` do servidor;
// apagar confirma citando o comentário; a falha deixa tudo como estava. Dados sintéticos.
vi.mock('dashboard/api/comentarioDaConversa', () => ({
  default: {
    get: vi.fn(),
    responder: vi.fn(),
    esconder: vi.fn(),
    apagar: vi.fn(),
  },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
const flags = { value: ['meta_ads_comentarios_ia', 'seus_posts_comentarios'] };
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    isCloudFeatureEnabled: flag => flags.value.includes(flag),
  }),
}));
const liberar = vi.fn();
const podeLiberar = { value: true };
vi.mock('dashboard/routes/dashboard/seusPosts/useLiberarAcesso', () => ({
  useLiberarAcesso: () => ({ podeLiberar, liberar }),
}));

const ok = (extra = {}) => ({
  data: {
    status: 'ok',
    comentario: {
      id: '18000000000000001',
      autor: '@cliente.exemplo',
      texto: 'Quanto custa?',
      quando: new Date().toISOString(),
      escondido: false,
      onde: 'post',
      ...extra,
    },
    pode: { responder: true, esconder: true, apagar: true },
  },
});

const montar = async () => {
  const wrapper = mount(ComentarioNaConversa, {
    props: { conversationId: 22, inboxId: 7 },
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale: 'pt_BR',
          messages: { pt_BR: ptBR },
        }),
      ],
    },
  });
  await flushPromises();
  return wrapper;
};

const acoes = wrapper =>
  wrapper
    .findAll('[data-comentario-acao]')
    .map(b => b.attributes('data-comentario-acao'));

describe('ComentarioNaConversa', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    flags.value = ['meta_ads_comentarios_ia', 'seus_posts_comentarios'];
    podeLiberar.value = true;
  });

  it('mostra o comentário com as três ações', async () => {
    api.get.mockResolvedValue(ok());
    const wrapper = await montar();

    expect(api.get).toHaveBeenCalledWith(22);
    expect(wrapper.find('[data-comentario-texto]').text()).toBe(
      'Quanto custa?'
    );
    expect(wrapper.text()).toContain('Comentário no post');
    expect(acoes(wrapper)).toEqual(['responder', 'esconder', 'apagar']);
  });

  it('sem a flag da IA dos comentários: nem cartão nem leitura', async () => {
    flags.value = [];
    const wrapper = await montar();

    expect(wrapper.find('[data-comentario-na-conversa]').exists()).toBe(false);
    expect(api.get).not.toHaveBeenCalled();
  });

  it('quem só lê vê o comentário, sem botões', async () => {
    const resposta = ok();
    resposta.data.pode = { responder: false, esconder: false, apagar: false };
    api.get.mockResolvedValue(resposta);
    const wrapper = await montar();

    expect(wrapper.find('[data-comentario-texto]').exists()).toBe(true);
    expect(acoes(wrapper)).toEqual([]);
  });

  it('responde em público e mostra a resposta; o campo fecha só no sucesso', async () => {
    api.get.mockResolvedValue(ok());
    api.responder.mockRejectedValueOnce({
      response: { data: { error: 'meta_refused' } },
    });
    api.responder.mockResolvedValueOnce({
      data: { resposta: { texto: 'Te mandei no direct' } },
    });
    const wrapper = await montar();

    await wrapper.find('[data-comentario-acao="responder"]').trigger('click');
    await wrapper.find('textarea').setValue('Te mandei no direct');
    await wrapper.find('[data-comentario-escrever]').trigger('submit');
    await flushPromises();
    expect(wrapper.find('textarea').element.value).toBe('Te mandei no direct');
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para fazer no Instagram. Tente de novo.'
    );

    await wrapper.find('[data-comentario-escrever]').trigger('submit');
    await flushPromises();
    expect(api.responder).toHaveBeenLastCalledWith(22, 'Te mandei no direct');
    expect(wrapper.find('textarea').exists()).toBe(false);
    expect(wrapper.find('[data-comentario-resposta]').text()).toContain(
      'Te mandei no direct'
    );
  });

  it('esconde e mostra de novo', async () => {
    api.get.mockResolvedValue(ok());
    api.esconder.mockImplementation((_id, hidden) =>
      Promise.resolve({ data: { escondido: hidden } })
    );
    const wrapper = await montar();

    await wrapper.find('[data-comentario-acao="esconder"]').trigger('click');
    await flushPromises();
    expect(api.esconder).toHaveBeenCalledWith(22, true);
    expect(wrapper.find('[data-comentario-selo-escondido]').exists()).toBe(
      true
    );
    expect(acoes(wrapper)).toEqual(['mostrar', 'apagar']);

    await wrapper.find('[data-comentario-acao="mostrar"]').trigger('click');
    await flushPromises();
    expect(api.esconder).toHaveBeenLastCalledWith(22, false);
    expect(wrapper.find('[data-comentario-selo-escondido]').exists()).toBe(
      false
    );
  });

  it('apagar confirma citando o comentário e só então apaga', async () => {
    api.get.mockResolvedValue(ok());
    api.apagar.mockResolvedValue({ data: { status: 'apagado' } });
    const wrapper = await montar();

    await wrapper.find('[data-comentario-acao="apagar"]').trigger('click');
    expect(wrapper.find('[data-comentario-confirmar-apagar]').text()).toContain(
      'Apagar o comentário de @cliente.exemplo: «Quanto custa?»?'
    );
    expect(api.apagar).not.toHaveBeenCalled();

    await wrapper.find('[data-comentario-apagar]').trigger('click');
    await flushPromises();
    expect(api.apagar).toHaveBeenCalledWith(22);
    expect(wrapper.find('[data-comentario-apagado]').exists()).toBe(true);
    expect(acoes(wrapper)).toEqual([]);
  });

  it('trocar de conversa fecha a resposta escrita para o comentário anterior', async () => {
    api.get.mockResolvedValue(ok());
    const wrapper = await montar();

    await wrapper.find('[data-comentario-acao="responder"]').trigger('click');
    await wrapper.find('textarea').setValue('Para a conversa 22');
    await wrapper.setProps({ conversationId: 23 });
    await flushPromises();

    expect(api.get).toHaveBeenLastCalledWith(23);
    expect(wrapper.find('[data-comentario-escrever]').exists()).toBe(false);
    await wrapper.find('[data-comentario-acao="responder"]').trigger('click');
    expect(wrapper.find('textarea').element.value).toBe('');
  });

  it('apagar que falha deixa a confirmação aberta e o comentário na tela', async () => {
    api.get.mockResolvedValue(ok());
    api.apagar.mockRejectedValue({
      response: { data: { error: 'meta_unavailable' } },
    });
    const wrapper = await montar();

    await wrapper.find('[data-comentario-acao="apagar"]').trigger('click');
    await wrapper.find('[data-comentario-apagar]').trigger('click');
    await flushPromises();

    expect(wrapper.find('[data-comentario-confirmar-apagar]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-comentario-apagado]').exists()).toBe(false);
  });

  it('comentário que sumiu do Instagram durante a ação vira apagado', async () => {
    api.get.mockResolvedValue(ok());
    api.esconder.mockRejectedValue({
      response: { data: { error: 'comment_not_found' } },
    });
    const wrapper = await montar();

    await wrapper.find('[data-comentario-acao="esconder"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-comentario-apagado]').exists()).toBe(true);
  });

  it('sem permissão: explica e libera pelo fluxo de Seus posts', async () => {
    api.get.mockResolvedValue({ data: { status: 'needs_permission' } });
    const wrapper = await montar();

    expect(wrapper.find('[data-comentario-sem-permissao]').exists()).toBe(true);
    await wrapper.find('[data-comentario-liberar]').trigger('click');
    expect(liberar).toHaveBeenCalled();
  });

  it('sem poder reautorizar (ou sem os comentários em Seus posts): pede a um administrador', async () => {
    flags.value = ['meta_ads_comentarios_ia'];
    api.get.mockResolvedValue({ data: { status: 'needs_permission' } });
    const wrapper = await montar();

    expect(wrapper.find('[data-comentario-liberar]').exists()).toBe(false);
    expect(wrapper.text()).toContain('Peça a um administrador');
  });

  it('Meta fora do ar: tentar de novo lê outra vez', async () => {
    api.get
      .mockRejectedValueOnce(new Error('rede'))
      .mockResolvedValueOnce(ok());
    const wrapper = await montar();

    expect(wrapper.attributes('data-estado')).toBe('meta_unavailable');
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.find('[data-comentario-texto]').exists()).toBe(true);
  });
});
