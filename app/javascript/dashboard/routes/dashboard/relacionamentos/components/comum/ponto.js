// O ponto que separa duas informações na mesma linha ("Funil › Etapa · de Fulano"). Fica aqui, e não solto no
// template, porque texto cru em template não passa no lint da casa.
export const PONTO = '·';
// Para quando o ponto fica sozinho dentro de um elemento: ali o template não guarda os espaços em volta.
export const SEPARADOR = ` ${PONTO} `;
