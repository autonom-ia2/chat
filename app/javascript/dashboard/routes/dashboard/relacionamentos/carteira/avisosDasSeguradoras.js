// #2900 (E7.5) — quais seguradoras da busca no Agger ganham aviso, na ordem
// em que os grupos aparecem na tela. Só as que têm evidência no cadastro de
// logins do Agger: o login guardado não vale mais (`pede_login`) ou a
// corretora não guardou o login (`sem_login`). Qualquer outra situação não
// ganha aviso: sem evidência, a tela não diz nada.
export const SITUACOES_COM_AVISO = ['pede_login', 'sem_login'];

export const comAviso = seguradoras =>
  seguradoras.filter(seguradora =>
    SITUACOES_COM_AVISO.includes(seguradora.situacao)
  );
