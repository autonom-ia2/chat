import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

// #1676 — com a flag crm_avaliar_toda_mensagem da conta (piloto 1, 16 e 18), a
// caixa de 1 funil também tem a IA de assunto em Automática (o servidor grava).
// Os textos acompanham: "à mão" vira "quando entender o assunto", com o mesmo
// texto da caixa de vários funis, e "assim que chega" diz que a IA dá o nome.
// Sem a flag, os textos de sempre: lá a IA de assunto segue desligada em 1 funil.
export const FLAG_IA_DE_ASSUNTO = 'crm_avaliar_toda_mensagem';

export const iaDeAssuntoLigada = conta =>
  conta?.features?.[FLAG_IA_DE_ASSUNTO] === true;

// O sufixo das chaves de CRM_CAIXAS.SOZINHO e CRM_CAIXAS.MODO_RESUMO. O valor
// gravado continua o mesmo ('chegou' ou 'off'): só o texto muda.
export const chaveDoModo = (modo, umFunil, iaDeAssunto) => {
  if (umFunil && iaDeAssunto && modo === 'off') return 'AUTO';
  if (umFunil && iaDeAssunto && modo === 'chegou') return 'CHEGOU_IA';
  return modo.toUpperCase();
};

export function useIaDeAssunto() {
  const conta = useMapGetter('accounts/getAccount');
  const contaId = useMapGetter('getCurrentAccountId');
  // Mesma leitura do useFase2: o getter da conta é uma função.
  return computed(
    () =>
      typeof conta.value === 'function' &&
      iaDeAssuntoLigada(conta.value(contaId.value))
  );
}
