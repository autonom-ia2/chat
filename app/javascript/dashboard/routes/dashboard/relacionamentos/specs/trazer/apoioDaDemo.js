import { aplicarConserto, aplicarDeixarDeFora } from '../../demo/trazer';

// Apoio dos specs que montam a tela com a planilha de exemplo da demonstração
// (demo/trazerPlanilha.js): as 8 linhas que precisam da pessoa e o valor que
// conserta cada uma. A demonstração confere o valor como o servidor, então o
// conserto tem de ser um valor que vale.
export const LINHAS_DA_DEMO = {
  TELEFONE: 14,
  EMAIL: 37,
  SEM_NOME: 62,
  // Telefone errado numa linha que também não tem nome.
  DOIS_PROBLEMAS: 96,
  // A fórmula está na empresa: a tela não conserta, a linha só fica de fora.
  FORMULA: 118,
  REPETIDA: 143,
  OUTRA_REPETIDA: 156,
  SEM_CONTATO: 171,
};

export const TELEFONE_QUE_VALE = '(11) 97380-0014';

// Na ordem: a linha com dois problemas é consertada duas vezes (o telefone e
// depois o nome), e na repetida o valor é a linha que fica.
const CONSERTOS = [
  [LINHAS_DA_DEMO.TELEFONE, TELEFONE_QUE_VALE],
  [LINHAS_DA_DEMO.EMAIL, 'rita.carvalhedo@exemplo.com.br'],
  [LINHAS_DA_DEMO.SEM_NOME, 'Ana Imbirussu'],
  [LINHAS_DA_DEMO.DOIS_PROBLEMAS, '(11) 96540-0096'],
  [LINHAS_DA_DEMO.DOIS_PROBLEMAS, 'Bruno Brandolim'],
  [LINHAS_DA_DEMO.REPETIDA, LINHAS_DA_DEMO.REPETIDA],
  [LINHAS_DA_DEMO.SEM_CONTATO, '(11) 98123-0171'],
];

// Nenhuma linha aberta: cada uma consertada, a da fórmula deixada de fora (é o
// que dá para fazer com ela) e a outra repetida de fora, porque de um grupo da
// mesma pessoa entra uma linha só. Cinco das consertadas são uma pessoa a mais;
// a repetida que fica é troca (a linha aprovada da mesma pessoa sai).
export const tudoResolvido = leitura =>
  aplicarDeixarDeFora(
    CONSERTOS.reduce(
      (atual, [linha, valor]) => aplicarConserto(atual, linha, valor),
      leitura
    ),
    LINHAS_DA_DEMO.FORMULA
  );
