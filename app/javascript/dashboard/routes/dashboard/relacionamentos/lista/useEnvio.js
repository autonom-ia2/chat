import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';

// #2894 — envio de uma ação em grupo: liga o "carregando" do botão e, se a fonte
// falhar, avisa com a frase que o diálogo escolheu e devolve null (a pessoa
// continua no diálogo e pode tentar de novo).
export const useEnvio = mensagemDeErro => {
  const enviando = ref(false);

  const enviar = async acao => {
    enviando.value = true;
    try {
      return await acao();
    } catch (erro) {
      useAlert(mensagemDeErro());
      return null;
    } finally {
      enviando.value = false;
    }
  };

  return { enviando, enviar };
};
