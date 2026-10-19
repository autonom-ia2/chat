// #1828: quem pediu para sair da cópia NESTA conversa (Crm::Email::Destinatarios, chave
// `email_saiu_da_copia` em additional_attributes) sai do Para/Cc/Cco que o painel preenche a partir do
// último e-mail. O cliente nunca sai; Para vazio volta a ser o cliente. Sem a chave, nada muda.
const normal = endereco =>
  String(endereco || '')
    .trim()
    .toLowerCase();

export const semQuemSaiuDaCopia = (destinos, saiu, contato) => {
  const fora = new Set((saiu || []).map(normal));
  fora.delete(normal(contato));
  if (!fora.size) return destinos;

  const manter = lista =>
    (lista || []).filter(endereco => !fora.has(normal(endereco)));
  const para = manter(destinos.to);
  return {
    to: para.length ? para : [contato].filter(Boolean),
    cc: manter(destinos.cc),
    bcc: manter(destinos.bcc),
  };
};
