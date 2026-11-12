// #2894 — para onde cada coluna da planilha pode ir, em palavras simples. O
// nome na tela vem do catálogo: RELACIONAMENTOS_TRAZER.DESTINOS.<id>.
export const DESTINOS = {
  NOME: 'nome',
  TELEFONE: 'telefone',
  TELEFONE_DA_EMPRESA: 'telefone_da_empresa',
  EMAIL: 'email',
  EMPRESA: 'empresa',
  CIDADE: 'cidade',
  CLIENTE: 'cliente',
  INFORMACAO: 'informacao',
  NAO_GUARDAR: 'nao_guardar',
};

export const LISTA_DE_DESTINOS = Object.values(DESTINOS);

// #2896 — o telefone da empresa só existe quando a leitura tem empresa (a
// planilha tem a coluna e a conta tem Empresas): sem ela, a tela não o oferece.
export const destinosDisponiveis = temEmpresa =>
  LISTA_DE_DESTINOS.filter(
    destino => temEmpresa || destino !== DESTINOS.TELEFONE_DA_EMPRESA
  );

// #2896 — a coluna que diz quem é cliente ("Algumas") é uma das que o sistema
// não usa para achar a pessoa: nome, telefone, e-mail e empresa não servem (o
// servidor recusa).
const DESTINOS_QUE_ACHAM_A_PESSOA = [
  DESTINOS.NOME,
  DESTINOS.TELEFONE,
  DESTINOS.EMAIL,
  DESTINOS.EMPRESA,
];

export const podeDizerQuemEhCliente = coluna =>
  !DESTINOS_QUE_ACHAM_A_PESSOA.includes(coluna.destino);

// #2896 — o que identifica a coluna é o índice dela na planilha: o nome pode
// repetir ou vir vazio.
export const chaveDaColuna = coluna => coluna.indice;

// #2896, Fatia 2 — a informação nova tem um campo: o nome dele (que já vem com o
// título da coluna) e o "para que serve" (opcional). O formato é o do servidor.
export const aparado = texto => String(texto ?? '').trim();

export const campoDaColuna = coluna => ({
  nome: aparado(coluna.campo?.nome ?? coluna.nome),
  para_que_serve: aparado(coluna.campo?.para_que_serve),
});
