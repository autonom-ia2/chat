// A tela aberta não fica sabendo do que o Guia fez pela API (#894). A pessoa
// pedia "crie a função", o Guia criava, e a lista seguia dizendo que não havia
// nenhuma. Cada mudança feita pelo Guia (executar, confirmar ou desfazer) sobe
// esta versão, e o painel remonta a página atual, que busca tudo de novo.
import { ref, readonly } from 'vue';

const versao = ref(0);

export const versaoDaConta = readonly(versao);

export const avisarContaMudou = () => {
  versao.value += 1;
};

// Um turno do Guia mudou a conta se ao menos um passo deu certo.
export const execucaoMudouConta = execucao =>
  Array.isArray(execucao?.passos) && execucao.passos.some(passo => passo.ok);
