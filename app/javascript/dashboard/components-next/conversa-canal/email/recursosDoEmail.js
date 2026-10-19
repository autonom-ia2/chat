// O que a conta tem para a conversa de e-mail (#1786): IA para ditar e algo que
// traduza (Google Tradutor ou a IA da conta). Uma consulta por conta, dividida entre
// todos os cartões e a caixa de resposta. Falhou: nada aparece (melhor que um botão
// que não faz nada).
import { ref } from 'vue';
import ConversaEmailAPI from 'dashboard/api/conversaEmail';

const recursos = ref({ ditado: false, traducao: false });
let consultaDaConta = null;
let contaConsultada = null;

export const useRecursosDoEmail = contaId => {
  if (contaId && contaId !== contaConsultada) {
    contaConsultada = contaId;
    consultaDaConta = ConversaEmailAPI.ditadoDisponivel()
      .then(({ data }) => {
        recursos.value = {
          ditado: Boolean(data.disponivel),
          traducao: Boolean(data.traducao),
        };
      })
      .catch(() => {
        recursos.value = { ditado: false, traducao: false };
      });
  }
  return { recursos, consulta: consultaDaConta };
};
