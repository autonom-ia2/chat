// Contatos compartilhados (#1702). Cada contato é um anexo `contact`: o nome em
// meta.firstName/lastName e o telefone em fallbackTitle (como bubbles/Contact.vue lê).
// #1709: quando o servidor manda também content_attributes.shared_contacts
// ([{ fullName, phones, waId }], igual ao attach_contact da Cloud), ela é a lista de
// verdade: um contato com dois telefones vira dois anexos, mas continua um contato só.
import { ATTACHMENT_TYPES } from '../../message/constants';

const listaCompartilhada = atributos =>
  Array.isArray(atributos?.sharedContacts)
    ? atributos.sharedContacts.filter(
        contato => contato && typeof contato === 'object'
      )
    : null;

export const variosContatos = (anexos, atributos) => {
  const compartilhados = listaCompartilhada(atributos);
  if (compartilhados?.length) return compartilhados.length > 1;
  return (
    Array.isArray(anexos) &&
    anexos.length > 1 &&
    anexos.every(anexo => anexo?.fileType === ATTACHMENT_TYPES.CONTACT)
  );
};

// Um contato só, com mais de um telefone (um anexo por telefone): o cartão de um
// contato, como o app, e não a lista nem o texto do conector.
export const umContatoComVariosTelefones = (anexos, atributos) =>
  listaCompartilhada(atributos)?.length === 1 &&
  Array.isArray(anexos) &&
  anexos.length > 1 &&
  anexos.every(anexo => anexo?.fileType === ATTACHMENT_TYPES.CONTACT);

const doAnexo = (anexo, posicao) => {
  const { firstName, lastName } = anexo?.meta || {};
  const telefone = anexo?.fallbackTitle || '';
  return {
    chave: anexo?.id ?? posicao,
    nome: `${firstName ?? ''} ${lastName ?? ''}`.trim(),
    telefone,
    telefones: telefone ? [telefone] : [],
  };
};

const doCompartilhado = (contato, posicao) => {
  const telefones = (Array.isArray(contato.phones) ? contato.phones : [])
    .map(telefone => String(telefone ?? '').trim())
    .filter(Boolean);
  return {
    chave: `compartilhado-${posicao}`,
    nome: typeof contato.fullName === 'string' ? contato.fullName.trim() : '',
    telefone: telefones[0] || '',
    telefones,
  };
};

export const contatosDoBalao = (anexos, atributos) => {
  const compartilhados = listaCompartilhada(atributos);
  if (compartilhados?.length) return compartilhados.map(doCompartilhado);
  return (Array.isArray(anexos) ? anexos : []).map(doAnexo);
};

const soDigitos = texto =>
  Array.from(String(texto ?? ''))
    .filter(caractere => caractere >= '0' && caractere <= '9')
    .join('');

// O número para "Conversar": o waId do WhatsApp (o número que tem WhatsApp de fato)
// do contato compartilhado dono deste telefone; sem ele, os dígitos do telefone.
export const numeroParaConversar = (telefone, atributos) => {
  const digitos = soDigitos(telefone);
  const compartilhados = listaCompartilhada(atributos) || [];
  const dono =
    compartilhados.find(contato =>
      (Array.isArray(contato.phones) ? contato.phones : []).some(
        numero => soDigitos(numero) === digitos
      )
    ) || (compartilhados.length === 1 ? compartilhados[0] : null);
  return soDigitos(dono?.waId) || digitos;
};
