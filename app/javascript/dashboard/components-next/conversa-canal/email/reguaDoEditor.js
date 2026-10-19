// #1872 — trocar só a régua do editor (o ✨ aparece quando a disponibilidade da IA chega), sem
// recriar o documento: state.reconfigure mantém o texto e o cursor, e os plugins de mesma chave
// (o histórico do desfazer) guardam o estado. O schema é o do próprio estado.
import { buildEditor } from '@chatwoot/prosemirror-schema';

export const trocarRegua = (state, opcoes) =>
  state.reconfigure({
    plugins: buildEditor({ ...opcoes, schema: state.schema }),
  });
