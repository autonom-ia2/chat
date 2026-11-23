import FidelidadeAPI from 'dashboard/api/fidelidade';
import RelacionamentosAPI from 'dashboard/api/relacionamentos';

// #3100 — as idas ao servidor da fidelidade, já com o corpo da resposta. Quem
// chama trata a falha (a tela diz o que deu errado e oferece tentar de novo).
// O cartão vai com os campos que o servidor aceita (Fidelidade::GravarPrograma);
// "a cada" vai em reais inteiros, como a tela fala.
const corpo = async pedido => (await pedido).data;

export const CAMPOS_DO_PROGRAMA = [
  'tipo',
  'a_cada',
  'ganha',
  'meta',
  'premio',
  'validade_meses',
];
export const programaParaOServidor = programa =>
  Object.fromEntries(
    CAMPOS_DO_PROGRAMA.map(campo => [
      campo,
      campo === 'premio' ? (programa.premio || '').trim() : programa[campo],
    ])
  );

export const lerPrograma = () => corpo(FidelidadeAPI.programa());
export const lerResumo = () => corpo(FidelidadeAPI.resumo());
export const salvarPrograma = programa =>
  corpo(FidelidadeAPI.salvarPrograma(programaParaOServidor(programa)));
export const ligarPrograma = ligado =>
  corpo(FidelidadeAPI.ligarPrograma(ligado));

export const fidelidadeDaPessoa = id =>
  corpo(RelacionamentosAPI.fidelidadeDaPessoa(id));
export const movimentosDaPessoa = (id, pagina) =>
  corpo(RelacionamentosAPI.movimentosDaPessoa(id, pagina));
// A mesma chave para o mesmo toque: quem chama gera uma por "Dar o prêmio".
export const darPremio = (id, chave) =>
  corpo(RelacionamentosAPI.darPremio(id, chave));

// O servidor recusa o prêmio sem o cartão completo (422 saldo_insuficiente).
export const semSaldo = falha =>
  falha?.response?.status === 422 &&
  falha.response.data?.error === 'saldo_insuficiente';
