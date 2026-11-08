import {
  CONVERSATION_PARTICIPATING_PERMISSIONS,
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  KEY_DEPENDENCIES,
} from 'dashboard/constants/permissions';

// Regras de chave que várias telas da conversa guiada leem (#2308). Os nomes das chaves vêm de constants/permissions;
// aqui fica só o que é regra destas telas, num lugar só.

// Os dois alcances de "Atende as próprias": pelo menos um fica ligado (toggleExtra).
export const ALCANCES_DE_CONVERSA = [
  CONVERSATION_UNASSIGNED_PERMISSIONS,
  CONVERSATION_PARTICIPATING_PERMISSIONS,
];

// Chave que só funciona com outra (KEY_DEPENDENCIES, #2075): as metas do mês sem os valores em R$ ficam inertes no
// servidor (MetasPolicy#manage?), então nenhuma tela as promete sozinhas (decisão 14A).
export const dependenciaDe = chave => KEY_DEPENDENCIES[chave] || null;
export const valeNoServidor = (chave, permissions) => {
  const dependencia = dependenciaDe(chave);
  return !dependencia || permissions.includes(dependencia);
};
