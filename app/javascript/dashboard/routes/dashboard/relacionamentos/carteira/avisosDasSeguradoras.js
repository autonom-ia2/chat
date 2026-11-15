// #2900 (E7.5) — quais seguradoras da busca no Agger ganham aviso, na ordem
// em que os grupos aparecem na tela. A seguradora pronta (ou ainda buscando)
// não ganha aviso.
export const SITUACOES_COM_AVISO = ['pede_login', 'sem_login', 'falhou'];

export const comAviso = seguradoras =>
  seguradoras.filter(seguradora =>
    SITUACOES_COM_AVISO.includes(seguradora.situacao)
  );

// Todas as seguradoras da busca ficaram com aviso: nenhuma buscou nada novo.
export const todasComAviso = seguradoras =>
  seguradoras.length > 0 && comAviso(seguradoras).length === seguradoras.length;
