// #3062 — o que o servidor recusou ao criar ou salvar uma pessoa, no formato
// que o formulário mostra embaixo de cada campo: { campo: chave do erro }. O
// contato responde 422 com a lista dos campos que não passaram (`attributes`),
// como a lista de contatos de hoje lê (store/modules/contacts/actions.js). Lá,
// e-mail e telefone que não passam são os repetidos: o formulário já conferiu
// o formato antes de mandar. Qualquer outra recusa volta vazia, e a tela dá o
// aviso geral.
const STATUS_RECUSADO = 422;

const CAMPOS_DO_SERVIDOR = [
  { doServidor: 'email', campo: 'email', erro: 'EMAIL_REPETIDO' },
  { doServidor: 'phone_number', campo: 'telefone', erro: 'TELEFONE_REPETIDO' },
];

export const camposRecusados = falha => {
  if (falha?.response?.status !== STATUS_RECUSADO) return {};
  const recusados = falha.response.data?.attributes ?? [];
  return Object.fromEntries(
    CAMPOS_DO_SERVIDOR.filter(({ doServidor }) =>
      recusados.includes(doServidor)
    ).map(({ campo, erro }) => [campo, erro])
  );
};
