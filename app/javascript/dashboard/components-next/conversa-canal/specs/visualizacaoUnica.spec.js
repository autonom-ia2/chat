// Visualização única do WhatsApp (#1702): com a pele, a mídia aparece com o "1" e
// "Visualização única" em cima; sem a pele, nada muda. Na lista, "Visualização única".
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerPele } from '../pele';
import {
  eVisualizacaoUnica,
  temVisualizacaoUnica,
  ultimaEVisualizacaoUnica,
} from '../visualizacaoUnica';
import MessagePreview from '../../Conversation/ConversationCard/MessagePreview.vue';
import MessagePreviewAntigo from '../../../components/widgets/conversation/MessagePreview.vue';
import { CAIXA_WHATSAPP, lojaDaLista } from './lojaDaLista';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const FOTO = { id: 9, fileType: 'image', dataUrl: 'https://x/foto.jpg' };

const montar = (pele, anexo) =>
  mount(
    defineComponent({
      setup() {
        fornecerPele(computed(() => pele));
        return () =>
          h(Message, {
            id: 1,
            messageType: MESSAGE_TYPES.INCOMING,
            status: MESSAGE_STATUS.SENT,
            content: null,
            conversationId: 7,
            createdAt: AGORA,
            currentUserId: 1,
            sender: { id: 3, name: 'Camila', type: 'Contact' },
            attachments: [anexo],
          });
      },
    }),
    { global: montagem }
  );

describe('eVisualizacaoUnica (#1702)', () => {
  it('lê a marca nas duas grafias do anexo', () => {
    expect(eVisualizacaoUnica({ isViewOnce: true })).toBe(true);
    expect(eVisualizacaoUnica({ is_view_once: true })).toBe(true);
    expect(eVisualizacaoUnica({ fileType: 'image' })).toBe(false);
    expect(eVisualizacaoUnica(undefined)).toBe(false);
    expect(temVisualizacaoUnica([{}, { isViewOnce: true }])).toBe(true);
    expect(temVisualizacaoUnica(undefined)).toBe(false);
    expect(
      ultimaEVisualizacaoUnica({ attachments: [{ is_view_once: true }] })
    ).toBe(true);
    expect(ultimaEVisualizacaoUnica({ attachments: [] })).toBe(false);
  });
});

describe('selo de visualização única na conversa (#1702)', () => {
  it('com a pele, mostra o selo e a própria foto', () => {
    const wrapper = montar(PELES.WHATSAPP, { ...FOTO, isViewOnce: true });
    const selo = wrapper.get('[data-visualizacao-unica]');

    expect(selo.text()).toContain('1');
    expect(selo.text()).toContain('CONVERSA_CANAL.VISUALIZACAO_UNICA.ROTULO');
    expect(
      wrapper.get('[data-bubble-name]').attributes('data-bubble-name')
    ).toBe('image');
  });

  it('foto comum, com a pele, fica sem o selo', () => {
    const wrapper = montar(PELES.WHATSAPP, FOTO);
    expect(wrapper.find('[data-visualizacao-unica]').exists()).toBe(false);
  });

  it('sem a pele, nada muda', () => {
    const wrapper = montar(null, { ...FOTO, isViewOnce: true });
    expect(wrapper.find('[data-visualizacao-unica]').exists()).toBe(false);
  });
});

describe('prévia na lista de conversas (#1702)', () => {
  const ultima = attachments => ({
    message_type: 0,
    content: null,
    inbox_id: CAIXA_WHATSAPP,
    attachments,
  });
  const montarPrevia = (Previa, attachments, ligada = true) =>
    mount(Previa, {
      props: { message: ultima(attachments) },
      global: {
        plugins: [lojaDaLista({ ligada })],
        stubs: { FluentIcon: true },
      },
    });

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])('com a pele, a prévia %s diz "Visualização única"', (_, Previa) => {
    expect(
      montarPrevia(Previa, [{ file_type: 'image', is_view_once: true }]).text()
    ).toContain('CONVERSA_CANAL.VISUALIZACAO_UNICA.ROTULO');
    expect(montarPrevia(Previa, [{ file_type: 'video' }]).text()).toContain(
      'CHAT_LIST.ATTACHMENTS.video.CONTENT'
    );
  });

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])('sem a pele, a prévia %s fica como na main', (_, Previa) => {
    const texto = montarPrevia(
      Previa,
      [{ file_type: 'image', is_view_once: true }],
      false
    ).text();
    expect(texto).not.toContain('CONVERSA_CANAL.VISUALIZACAO_UNICA.ROTULO');
    expect(texto).toContain('CHAT_LIST.ATTACHMENTS.image.CONTENT');
  });
});
