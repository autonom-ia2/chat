import { mount, flushPromises, enableAutoUnmount } from '@vue/test-utils';
import CrmContatoRelacaoAPI from 'dashboard/api/crmContatoRelacao';
import ChoiceSelect from 'dashboard/components-next/choice-select/ChoiceSelect.vue';
import { useAlert } from 'dashboard/composables';
import { criarI18n } from 'dashboard/components-next/painel-do-contato/specs/apoio';
import EscolhaDaRelacao from '../EscolhaDaRelacao.vue';

// #2084/#2085 — "Este contato é": lê do servidor, muda pela escolha, pergunta
// "Arquivar?" só quando sai do funil com card aberto, e só deixa mudar quem a
// tela e o servidor deixam.
vi.mock('dashboard/api/crmContatoRelacao', () => ({
  default: { show: vi.fn(), update: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const abrir = vi.fn();
const fechar = vi.fn();
const DialogStub = {
  emits: ['confirm', 'close'],
  methods: { open: abrir, close: fechar },
  template: '<div data-test-id="pergunta" />',
};

const lido = dados => ({
  data: { relacao: 'interessado', cardsAbertos: 0, podeEditar: true, ...dados },
});

const montar = (props = {}) =>
  mount(EscolhaDaRelacao, {
    props: { contactId: 9, podeEditar: true, ...props },
    global: { plugins: [criarI18n()], stubs: { Dialog: DialogStub } },
  });

const escolher = async (wrapper, relacao) => {
  const escolha = wrapper.findComponent(ChoiceSelect);
  escolha.vm.$emit('update:modelValue', relacao);
  escolha.vm.$emit('change', relacao);
  await flushPromises();
};

enableAutoUnmount(afterEach);
beforeEach(() => vi.clearAllMocks());

describe('EscolhaDaRelacao', () => {
  it('mostra a frase do que a escolha faz', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido({ relacao: 'parceiro' }));
    const wrapper = montar();
    await flushPromises();

    expect(CrmContatoRelacaoAPI.show).toHaveBeenCalledWith(9);
    expect(wrapper.find('[data-test-id="efeito-da-relacao"]').text()).toContain(
      'não viram card sozinhas'
    );
  });

  it('sem card aberto, grava direto e avisa', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido());
    CrmContatoRelacaoAPI.update.mockResolvedValue({
      data: { relacao: 'parceiro', cardsArquivados: 0, cardsNaoArquivados: 0 },
    });
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'parceiro');

    expect(abrir).not.toHaveBeenCalled();
    expect(CrmContatoRelacaoAPI.update).toHaveBeenCalledWith(9, {
      relacao: 'parceiro',
      arquivarCards: false,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Agora este contato é Parceiro do mercado.'
    );
  });

  it('com card aberto, pergunta e arquiva quando a pessoa escolhe Arquivar', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido({ cardsAbertos: 2 }));
    CrmContatoRelacaoAPI.update.mockResolvedValue({
      data: {
        relacao: 'nao_e_negocio',
        cardsArquivados: 2,
        cardsNaoArquivados: 0,
      },
    });
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'nao_e_negocio');
    expect(abrir).toHaveBeenCalled();
    expect(CrmContatoRelacaoAPI.update).not.toHaveBeenCalled();

    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(CrmContatoRelacaoAPI.update).toHaveBeenCalledWith(9, {
      relacao: 'nao_e_negocio',
      arquivarCards: true,
    });
    expect(useAlert).toHaveBeenCalledWith(
      'Agora este contato é Não é negócio. 2 cards arquivados.'
    );
  });

  it('com Deixar, grava sem arquivar', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido({ cardsAbertos: 1 }));
    CrmContatoRelacaoAPI.update.mockResolvedValue({
      data: { relacao: 'parceiro', cardsArquivados: 0, cardsNaoArquivados: 0 },
    });
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'parceiro');
    wrapper.findComponent(DialogStub).vm.$emit('close');
    await flushPromises();

    expect(CrmContatoRelacaoAPI.update).toHaveBeenCalledWith(9, {
      relacao: 'parceiro',
      arquivarCards: false,
    });
  });

  it('avisa os cards que ficaram abertos porque a regra não deixou arquivar', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido({ cardsAbertos: 2 }));
    CrmContatoRelacaoAPI.update.mockResolvedValue({
      data: { relacao: 'parceiro', cardsArquivados: 1, cardsNaoArquivados: 1 },
    });
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'parceiro');
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    await flushPromises();

    expect(useAlert).toHaveBeenCalledWith(
      'Agora este contato é Parceiro do mercado. 1 card arquivado. 1 card ficou aberto: você não pode arquivá-lo.'
    );
  });

  it('trocar de contato com a pergunta aberta não grava nada', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido({ cardsAbertos: 1 }));
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'parceiro');
    await wrapper.setProps({ contactId: 10 });
    await flushPromises();
    wrapper.findComponent(DialogStub).vm.$emit('confirm');
    wrapper.findComponent(DialogStub).vm.$emit('close');
    await flushPromises();

    expect(fechar).toHaveBeenCalled();
    expect(CrmContatoRelacaoAPI.update).not.toHaveBeenCalled();
    expect(CrmContatoRelacaoAPI.show).toHaveBeenLastCalledWith(10);
  });

  it('entre Parceiro e Não é negócio não pergunta de novo', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(
      lido({ relacao: 'parceiro', cardsAbertos: 1 })
    );
    CrmContatoRelacaoAPI.update.mockResolvedValue({
      data: {
        relacao: 'nao_e_negocio',
        cardsArquivados: 0,
        cardsNaoArquivados: 0,
      },
    });
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'nao_e_negocio');

    expect(abrir).not.toHaveBeenCalled();
    expect(CrmContatoRelacaoAPI.update).toHaveBeenCalledWith(9, {
      relacao: 'nao_e_negocio',
      arquivarCards: false,
    });
  });

  it.each([401, 403, 404])(
    'some quando o servidor responde %s (o pai esconde o título)',
    async status => {
      CrmContatoRelacaoAPI.show.mockRejectedValue(
        Object.assign(new Error('x'), { response: { status } })
      );
      const wrapper = montar();
      await flushPromises();

      expect(wrapper.emitted('estado').at(-1)).toEqual(['escondido']);
      expect(wrapper.text()).not.toContain('Não deu para');
    }
  );

  it('volta a escolha e avisa quando o servidor recusa', async () => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido());
    CrmContatoRelacaoAPI.update.mockRejectedValue(new Error('x'));
    const wrapper = montar();
    await flushPromises();

    await escolher(wrapper, 'parceiro');

    expect(wrapper.findComponent(ChoiceSelect).props('modelValue')).toBe(
      'interessado'
    );
    expect(useAlert).toHaveBeenCalledWith(
      'Não deu para mudar agora. Tente de novo.'
    );
  });

  it.each([
    ['a tela não deixa', { podeEditar: false }, {}],
    ['o servidor não deixa', {}, { podeEditar: false }],
  ])('só mostra a relação quando %s', async (_caso, props, dados) => {
    CrmContatoRelacaoAPI.show.mockResolvedValue(lido(dados));
    const wrapper = montar(props);
    await flushPromises();

    expect(wrapper.findComponent(ChoiceSelect).exists()).toBe(false);
    expect(wrapper.text()).toContain('Interessado');
  });
});
