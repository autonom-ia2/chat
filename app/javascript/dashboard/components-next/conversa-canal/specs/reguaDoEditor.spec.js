// #1872 — quando a disponibilidade da IA chega depois de a pessoa digitar, só a régua muda.
import {
  EditorState,
  MessageMarkdownTransformer,
  Selection,
  buildEditor,
  buildMessageSchema,
} from '@chatwoot/prosemirror-schema';
import { getFormattingForEditor } from 'dashboard/helper/editorHelper';
import { trocarRegua } from '../email/reguaDoEditor';

const formato = getFormattingForEditor('Channel::Email', true);
const schema = buildMessageSchema(formato.marks, formato.nodes);
const MENU_SEM_IA = ['strong', 'em', 'undo', 'redo'];
const MENU_COM_IA = ['copilot', ...MENU_SEM_IA];

const estadoDigitado = () => {
  const inicial = EditorState.create({
    doc: new MessageMarkdownTransformer(schema).parse('Oi Marina'),
    plugins: buildEditor({ schema, enabledMenuOptions: MENU_SEM_IA }),
  });
  // A pessoa digitou no fim e o cursor ficou no meio.
  const digitado = inicial.apply(
    inicial.tr.insertText(', tudo bem?', inicial.doc.content.size - 1)
  );
  return digitado.apply(
    digitado.tr.setSelection(Selection.near(digitado.doc.resolve(3)))
  );
};

const historico = estado =>
  estado.plugins.find(plugin => plugin.key.startsWith('history$'));

describe('trocarRegua', () => {
  it('mantém o texto, o cursor e o histórico do desfazer', () => {
    const antes = estadoDigitado();
    const depois = trocarRegua(antes, { enabledMenuOptions: MENU_COM_IA });

    expect(depois.doc.eq(antes.doc)).toBe(true);
    expect(depois.doc.textContent).toBe('Oi Marina, tudo bem?');
    expect(depois.selection.eq(antes.selection)).toBe(true);
    expect(historico(depois).getState(depois)).toBe(
      historico(antes).getState(antes)
    );
  });

  it('troca os plugins da régua (é ela que passa a ter o ✨)', () => {
    const antes = estadoDigitado();
    const depois = trocarRegua(antes, { enabledMenuOptions: MENU_COM_IA });

    expect(depois.plugins).not.toEqual(antes.plugins);
    expect(depois.schema).toBe(antes.schema);
  });
});
