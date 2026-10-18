// Figurinha do WhatsApp (#1702): com a pele, solta, sem balão, sem bico e com a hora
// num selo; sem a pele, a foto de sempre. Na lista de conversas, "Figurinha".
import { computed, defineComponent, h } from 'vue';
import { mount } from '@vue/test-utils';
import Message from '../../message/Message.vue';
import { MESSAGE_STATUS, MESSAGE_TYPES } from '../../message/constants';
import { AGORA, montagem } from '../../message/specs/montarMensagem';
import { PELES, fornecerPele } from '../pele';
import { eFigurinha, ultimaEFigurinha } from '../figurinha';
import {
  FIGURINHA,
  classesDaHora,
  classesDoBalao,
  temBico,
} from '../visualWhatsapp';
import { podeEntrarNoAlbum } from '../album/agruparAlbuns';
import FigurinhaDoWhatsapp from '../midia/FigurinhaDoWhatsapp.vue';
import MessagePreview from '../../Conversation/ConversationCard/MessagePreview.vue';
import MessagePreviewAntigo from '../../../components/widgets/conversation/MessagePreview.vue';
import { CAIXA_WHATSAPP, lojaDaLista } from './lojaDaLista';

vi.mock('vue-router', () => ({ useRoute: () => ({ query: {}, params: {} }) }));

const ANEXO_FIGURINHA = {
  id: 9,
  fileType: 'image',
  dataUrl: 'https://x/figurinha.webp',
  isSticker: true,
};

const montarComPele = (pele, props = {}) =>
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
            attachments: [ANEXO_FIGURINHA],
            ...props,
          });
      },
    }),
    { global: montagem }
  );

describe('eFigurinha (#1702)', () => {
  it('lê a marca nas duas grafias do anexo', () => {
    expect(eFigurinha({ isSticker: true })).toBe(true);
    expect(eFigurinha({ is_sticker: true })).toBe(true);
    expect(eFigurinha({ fileType: 'image' })).toBe(false);
    expect(eFigurinha(undefined)).toBe(false);
    expect(ultimaEFigurinha({ attachments: [{ is_sticker: true }] })).toBe(
      true
    );
    expect(ultimaEFigurinha({ attachments: [] })).toBe(false);
    expect(ultimaEFigurinha({})).toBe(false);
  });
});

describe('visual da figurinha (#1702)', () => {
  const recebida = {
    variante: 'user',
    lado: 'left',
    primeira: true,
    nomeDoBalao: FIGURINHA,
  };

  it('o balão some: sem fundo, sem sombra e sem moldura', () => {
    const classes = classesDoBalao(recebida);
    expect(classes).toContain('!bg-transparent');
    expect(classes).toContain('!shadow-none');
    expect(classes).toContain('!p-0');
    expect(classes).toContain('mt-[10px]');
    expect(classes).not.toContain('!bg-white');
    expect(classesDoBalao({ ...recebida, primeira: false })).not.toContain(
      'mt-[10px]'
    );
  });

  it('não tem bico, nem no primeiro da sequência', () => {
    expect(temBico(recebida)).toBe(false);
    expect(temBico({ ...recebida, nomeDoBalao: 'image' })).toBe(true);
  });

  it('a hora fica num selo da cor do balão, no canto de baixo', () => {
    const doCliente = classesDaHora(recebida);
    expect(doCliente).toContain('absolute');
    expect(doCliente).toContain('bottom-[3px]');
    expect(doCliente).toContain('bg-white');
    const daEmpresa = classesDaHora({ ...recebida, variante: 'agent' });
    expect(daEmpresa).toContain('bg-[#D9FDD3]');
  });

  it('não entra em álbum', () => {
    const mensagem = {
      messageType: 0,
      attachments: [ANEXO_FIGURINHA],
      contentAttributes: {},
    };
    expect(podeEntrarNoAlbum(mensagem)).toBe(false);
    const foto = {
      messageType: 0,
      attachments: [{ ...ANEXO_FIGURINHA, isSticker: false }],
    };
    expect(podeEntrarNoAlbum(foto)).toBe(true);
  });
});

describe('FigurinhaDoWhatsapp (#1702)', () => {
  it('reserva 190 px e mostra a figurinha depois de carregar', () => {
    const vazia = mount(FigurinhaDoWhatsapp, {
      props: { attachment: ANEXO_FIGURINHA },
    });
    expect(vazia.classes()).toContain('size-[190px]');
    expect(vazia.find('img').exists()).toBe(false);

    const pronta = mount(FigurinhaDoWhatsapp, {
      props: { attachment: ANEXO_FIGURINHA, carregada: true },
    });
    const img = pronta.get('img');
    expect(img.attributes('src')).toBe(ANEXO_FIGURINHA.dataUrl);
    expect(img.attributes('alt')).toBe('CONVERSA_CANAL.MIDIA.FIGURINHA');
    expect(img.classes()).toContain('object-contain');
  });
});

describe('figurinha na conversa (#1702)', () => {
  it('com a pele do WhatsApp: solta, sem bico', () => {
    const wrapper = montarComPele(PELES.WHATSAPP);
    const balao = wrapper.get('[data-bubble-name]');

    expect(balao.attributes('data-bubble-name')).toBe('sticker');
    expect(balao.classes()).toContain('!bg-transparent');
    expect(balao.classes()).not.toContain('p-3');
    expect(wrapper.find('[data-figurinha-do-whatsapp]').exists()).toBe(true);
    expect(wrapper.find('svg[viewBox="0 0 8 13"]').exists()).toBe(false);
  });

  it('sem a pele: a foto de sempre', () => {
    const wrapper = montarComPele(null);
    const balao = wrapper.get('[data-bubble-name]');

    expect(balao.attributes('data-bubble-name')).toBe('image');
    expect(balao.classes()).toContain('p-3');
    expect(wrapper.find('[data-figurinha-do-whatsapp]').exists()).toBe(false);
  });

  it('foto comum com a pele continua foto', () => {
    const wrapper = montarComPele(PELES.WHATSAPP, {
      attachments: [{ ...ANEXO_FIGURINHA, isSticker: undefined }],
    });

    expect(
      wrapper.get('[data-bubble-name]').attributes('data-bubble-name')
    ).toBe('image');
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
  ])('com a pele, a prévia %s diz "Figurinha"', (_, Previa) => {
    expect(
      montarPrevia(Previa, [{ file_type: 'image', is_sticker: true }]).text()
    ).toContain('CONVERSA_CANAL.MIDIA.FIGURINHA');
    expect(montarPrevia(Previa, [{ file_type: 'image' }]).text()).toContain(
      'CHAT_LIST.ATTACHMENTS.image.CONTENT'
    );
  });

  it.each([
    ['nova', MessagePreview],
    ['antiga', MessagePreviewAntigo],
  ])('sem a pele, a prévia %s fica como na main', (_, Previa) => {
    const texto = montarPrevia(
      Previa,
      [{ file_type: 'image', is_sticker: true }],
      false
    ).text();
    expect(texto).not.toContain('CONVERSA_CANAL.MIDIA.FIGURINHA');
    expect(texto).toContain('CHAT_LIST.ATTACHMENTS.image.CONTENT');
  });
});
