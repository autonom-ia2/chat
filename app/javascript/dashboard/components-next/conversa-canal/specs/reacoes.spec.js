import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/conversaCanal.json';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerPele } from '../pele';
import SeloDeReacoes from '../SeloDeReacoes.vue';
import {
  agruparReacoes,
  descreverReacoes,
  ehReacaoDoAgente,
  reacoesDaMensagem,
} from '../reacoes';

const doCliente = emoji => ({ emoji, senderType: 'Contact', senderId: 7 });
const daEquipe = emoji => ({ emoji, senderType: 'User', senderId: 3 });

const i18n = () =>
  createI18n({ legacy: false, locale: 'en', messages: { en } });

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const montarMensagem = (pele, contentAttributes) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => pele));
        return () =>
          h(Message, {
            id: 1,
            messageType: MESSAGE_TYPES.OUTGOING,
            status: MESSAGE_STATUS.READ,
            content: 'Segue a proposta',
            conversationId: 7,
            createdAt: AGORA,
            currentUserId: 1,
            sender: { id: 1, name: 'Marina', type: 'User' },
            contentAttributes,
          });
      },
    }),
    { global: montagem }
  );

const montar = props =>
  mount(SeloDeReacoes, {
    props,
    global: { plugins: [i18n()] },
  });

describe('reações do WhatsApp (#1702)', () => {
  it('lê só as reações com emoji', () => {
    expect(reacoesDaMensagem(undefined)).toEqual([]);
    expect(reacoesDaMensagem({ reactions: 'x' })).toEqual([]);
    expect(
      reacoesDaMensagem({ reactions: [doCliente('👍'), { emoji: '' }, null] })
    ).toEqual([doCliente('👍')]);
  });

  it('agrupa por emoji na ordem em que apareceu', () => {
    expect(
      agruparReacoes([doCliente('👍'), daEquipe('❤️'), daEquipe('👍')])
    ).toEqual([
      { emoji: '👍', total: 2 },
      { emoji: '❤️', total: 1 },
    ]);
  });

  it('reconhece a mensagem sintética do agente da Autonomia', () => {
    expect(
      ehReacaoDoAgente({
        contentAttributes: { autonomiaReaction: { emoji: '👍' } },
      })
    ).toBe(true);
    expect(ehReacaoDoAgente({ contentAttributes: {} })).toBe(false);
    expect(ehReacaoDoAgente(null)).toBe(false);
  });

  it('descreve quem reagiu, com o nome do cliente', () => {
    const { global } = i18n();
    expect(
      descreverReacoes([doCliente('👍'), daEquipe('❤️')], {
        t: global.t,
        nomeDoCliente: 'Maria',
      })
    ).toBe('Maria reacted with 👍; Team reacted with ❤️');
    expect(
      descreverReacoes([doCliente('👍')], { t: global.t, nomeDoCliente: '' })
    ).toBe('Customer reacted with 👍');
  });

  describe('selo', () => {
    it('mostra o emoji, sem contagem quando é uma reação só', () => {
      const selo = montar({
        reacoes: [doCliente('👍')],
        nomeDoCliente: 'Maria',
      }).find('[data-selo-de-reacoes]');

      expect(selo.text()).toBe('👍');
      expect(selo.attributes('role')).toBe('img');
      expect(selo.attributes('aria-label')).toBe('Maria reacted with 👍');
      expect(selo.attributes('title')).toBe('Maria reacted with 👍');
    });

    it('mostra até 3 emojis diferentes e o total', () => {
      const selo = montar({
        reacoes: ['👍', '❤️', '😂', '🙏', '👍'].map(daEquipe),
      }).find('[data-selo-de-reacoes]');

      const emojis = selo
        .findAll('span[aria-hidden="true"]')
        .map(s => s.text());
      expect(emojis).toEqual(['👍', '❤️', '😂', '5']);
    });

    it('fica no canto de baixo do lado do balão, claro e escuro', () => {
      const recebida = montar({ reacoes: [doCliente('👍')], lado: 'left' });
      const enviada = montar({ reacoes: [doCliente('👍')], lado: 'right' });
      const classes = recebida.find('[data-selo-de-reacoes]').classes();

      expect(classes).toEqual(
        expect.arrayContaining([
          'absolute',
          '-bottom-[18px]',
          'rounded-full',
          'bg-white',
          'dark:bg-[#242626]',
          'ltr:left-2',
        ])
      );
      expect(enviada.find('[data-selo-de-reacoes]').classes()).toContain(
        'ltr:right-2'
      );
    });
  });

  describe('no balão', () => {
    const comReacao = { reactions: [doCliente('👍')] };

    it('com a pele, o selo aparece embaixo do balão reagido', () => {
      const wrapper = montarMensagem(PELES.WHATSAPP, comReacao);
      expect(wrapper.find('[data-selo-de-reacoes]').text()).toBe('👍');
      expect(wrapper.find('.mb-\\[18px\\]').exists()).toBe(true);
    });

    it('sem a pele, nada muda', () => {
      const wrapper = montarMensagem(null, comReacao);
      expect(wrapper.find('[data-selo-de-reacoes]').exists()).toBe(false);
      expect(wrapper.find('.mb-\\[18px\\]').exists()).toBe(false);
    });

    it('sem reação, sem selo', () => {
      const wrapper = montarMensagem(PELES.WHATSAPP, {});
      expect(wrapper.find('[data-selo-de-reacoes]').exists()).toBe(false);
    });
  });
});
