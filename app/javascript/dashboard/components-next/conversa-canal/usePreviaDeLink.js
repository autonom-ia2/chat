// A prévia de link do balão (#1702), só com a pele do WhatsApp. Sem pele (chave
// desligada, outro canal), nada aparece, mesmo que a mensagem tenha a prévia gravada.
import { computed } from 'vue';
import { useMessageContext } from '../message/provider.js';
import { PELES, usePele } from './pele';
import { previaDeLink } from './previaDeLink';

export const usePreviaDeLink = () => {
  const pele = usePele();
  const { contentAttributes } = useMessageContext();

  return computed(() =>
    pele.value === PELES.WHATSAPP ? previaDeLink(contentAttributes.value) : null
  );
};
