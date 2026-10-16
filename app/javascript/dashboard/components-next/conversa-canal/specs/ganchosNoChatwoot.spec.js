// A pele do WhatsApp (#1702) muda peças do Chatwoot pelas classes que elas já têm
// (visualWhatsapp.js e usePeleDaResposta.js). Se uma atualização do Chatwoot tirar
// ou renomear uma dessas classes, a pele para de funcionar sem nenhum erro. Este
// teste falha antes: diz qual arquivo do Chatwoot perdeu qual classe.
import Message from '../../message/Message.vue?raw';
import Base from '../../message/bubbles/Base.vue?raw';
import BaseAttachment from '../../message/bubbles/BaseAttachment.vue?raw';
import Frame from '../../message/bubbles/RichMessage/Frame.vue?raw';
import ActionRow from '../../message/bubbles/RichMessage/ActionRow.vue?raw';
import LinkButton from '../../message/bubbles/RichMessage/types/LinkButton.vue?raw';
import ChipImage from '../../message/chips/Image.vue?raw';
import ChipAudio from '../../message/chips/Audio.vue?raw';
import ReplyBottomPanel from '../../../components/widgets/WootWriter/ReplyBottomPanel.vue?raw';
import ReplyTopPanel from '../../../components/widgets/WootWriter/ReplyTopPanel.vue?raw';
import Editor from '../../../components/widgets/WootWriter/Editor.vue?raw';

const GANCHOS = [
  ['message/Message.vue', Message, ['[grid-area:avatar]']],
  ['message/bubbles/Base.vue', Base, ['prose-bubble', 'bg-n-alpha-black1']],
  [
    'message/bubbles/BaseAttachment.vue',
    BaseAttachment,
    ['min-w-64', 'gap-3', 'size-8', 'space-y-1', 'bg-n-solid-3'],
  ],
  [
    'message/bubbles/RichMessage/Frame.vue',
    Frame,
    ['class="flex flex-col gap-1"'],
  ],
  ['message/bubbles/RichMessage/ActionRow.vue', ActionRow, ['bg-n-solid-3']],
  [
    'message/bubbles/RichMessage/types/LinkButton.vue',
    LinkButton,
    ['break-all'],
  ],
  ['message/chips/Image.vue', ChipImage, ['contain-content']],
  ['message/chips/Audio.vue', ChipAudio, ['border-n-container']],
  [
    'widgets/WootWriter/ReplyBottomPanel.vue',
    ReplyBottomPanel,
    [
      'left-wrap',
      'right-wrap',
      'file-uploads',
      'i-ph-microphone',
      'conversationAttachment',
    ],
  ],
  [
    'widgets/WootWriter/ReplyTopPanel.vue',
    ReplyTopPanel,
    ['i-lucide-maximize-2'],
  ],
  ['widgets/WootWriter/Editor.vue', Editor, ['resizable-editor-body']],
];

describe('ganchos da pele do WhatsApp no Chatwoot (#1702)', () => {
  it.each(GANCHOS)(
    '%s ainda tem as classes que a pele usa',
    (_, fonte, classes) => {
      const faltando = classes.filter(classe => !fonte.includes(classe));
      expect(faltando).toEqual([]);
    }
  );
});
