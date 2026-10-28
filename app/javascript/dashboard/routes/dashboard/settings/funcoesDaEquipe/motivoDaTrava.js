import {
  DELEGATION_KEYS,
  KEY_DEPENDENCIES,
} from 'dashboard/constants/permissions';
import { LOCK_REASONS, reachesKeys } from 'dashboard/helper/peopleAccess';

// Por que quem dá não pode pôr esta chave numa função (#2308, especificação 7.3). Testa a chave e a dependência dela
// separadamente; se alguma travada é de delegação, o motivo é DELEGATION, mesmo que outra falte. O keyLockReason
// devolve a primeira travada: para a Carla, metas do mês dariam MISSING, e ela pediria uma chave que não resolve.
const travadas = (giver, chaves) =>
  chaves.filter(chave => !reachesKeys(giver, [chave]));

const comDependencias = chaves =>
  chaves.flatMap(chave =>
    KEY_DEPENDENCIES[chave] ? [chave, KEY_DEPENDENCIES[chave]] : [chave]
  );

// O motivo de um grupo de chaves, com DELEGATION vencendo MISSING; null quando quem dá alcança todas.
export const motivoDasChaves = (giver, chaves) => {
  const presas = travadas(giver, comDependencias(chaves));
  if (!presas.length) return null;
  return presas.some(chave => DELEGATION_KEYS.includes(chave))
    ? LOCK_REASONS.DELEGATION
    : LOCK_REASONS.MISSING;
};

export const motivoDaTrava = (giver, chave) => motivoDasChaves(giver, [chave]);

// Chave i18n de FUNCOES_EQUIPE.TRAVA para o motivo.
export const TEXTO_DA_TRAVA = {
  [LOCK_REASONS.DELEGATION]: 'SO_ADMIN',
  [LOCK_REASONS.MISSING]: 'NAO_TEM',
};
