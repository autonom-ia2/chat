// #2896 — a demonstração recusa uma escrita como o servidor: com o código dele
// (`error` e, no valor que não vale, `motivo`). Quem dá nome à recusa é a
// tradução da fonte real (fonte/trazerTraducao.js, `erroDaEscrita`): assim a
// tela recebe das duas fontes o mesmo erro, com o mesmo nome.
import { erroDaEscrita } from '../fonte/trazerTraducao';

const STATUS_DA_RECUSA = 422;
const VALOR_INVALIDO = 'valor_invalido';

export const recusa = (error, motivo) =>
  erroDaEscrita({
    response: {
      status: STATUS_DA_RECUSA,
      data: motivo ? { error, motivo } : { error },
    },
  });

export const valorInvalido = motivo => recusa(VALOR_INVALIDO, motivo);
