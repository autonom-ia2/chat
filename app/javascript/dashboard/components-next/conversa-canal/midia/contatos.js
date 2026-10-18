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

// Vários contatos numa mensagem da Cloud (#1702): o cliente manda 2+ contatos de uma
// vez e o Chatwoot cria UMA mensagem por contato, todas com o mesmo source_id
// (Whatsapp::IncomingContactMessageHandler). Como no álbum, a 1ª desenha o cartão
// "Fulano e N outros contatos" e as outras somem da lista.
const soContatos = mensagem =>
  Array.isArray(mensagem?.attachments) &&
  mensagem.attachments.length > 0 &&
  mensagem.attachments.every(
    anexo => anexo?.fileType === ATTACHMENT_TYPES.CONTACT
  );

const doMesmoEnvio = (anterior, atual) =>
  Boolean(atual.sourceId) &&
  atual.sourceId === anterior.sourceId &&
  atual.messageType === anterior.messageType &&
  !atual.private &&
  !anterior.private;

// O Chatwoot descarta, no WhatsApp, mensagem com source_id repetido (eco duplicado do
// webhook: filterDuplicateSourceMessages). Os contatos de um mesmo envio repetem o
// source_id de propósito (uma mensagem por contato, mesmo quando o cliente manda o mesmo
// contato duas vezes), e o 2º, 3º… sumiam antes de chegar ao cartão. Com a pele, a
// mensagem só de contatos fica sempre; o resto segue o filtro do Chatwoot. Lista crua
// do servidor (snake_case).
const soContatosCru = mensagem =>
  Array.isArray(mensagem?.attachments) &&
  mensagem.attachments.length > 0 &&
  mensagem.attachments.every(
    anexo => anexo?.file_type === ATTACHMENT_TYPES.CONTACT
  );

export const semDuplicadasNaPele = (mensagens = []) => {
  const vistas = new Set();
  return mensagens.filter(mensagem => {
    if (!mensagem.source_id || soContatosCru(mensagem)) return true;
    if (vistas.has(mensagem.source_id)) return false;
    vistas.add(mensagem.source_id);
    return true;
  });
};

// Map: id da 1ª mensagem -> mensagens de contato seguidas com o mesmo sourceId, na
// ordem do envio (id crescente: o 1º contato que o cliente escolheu abre o cartão).
export const agruparContatos = lista => {
  const grupos = new Map();
  let bloco = [];
  const fechar = () => {
    if (bloco.length > 1) {
      grupos.set(
        bloco[0].id,
        [...bloco].sort((a, b) => a.id - b.id)
      );
    }
    bloco = [];
  };
  lista.forEach(mensagem => {
    const anterior = bloco.at(-1);
    if (!soContatos(mensagem)) {
      fechar();
      return;
    }
    if (anterior && !doMesmoEnvio(anterior, mensagem)) fechar();
    bloco.push(mensagem);
  });
  fechar();
  return grupos;
};

// Os contatos de uma mensagem do grupo. Na Cloud cada mensagem é UM contato, com um
// anexo por telefone; com shared_contacts (#1709), a lista dela.
const contatosDeUmaMensagem = mensagem => {
  const atributos = mensagem.contentAttributes || {};
  if (listaCompartilhada(atributos)?.length) {
    return contatosDoBalao(mensagem.attachments, atributos);
  }
  const [primeiro] = contatosDoBalao(mensagem.attachments, atributos);
  const telefones = mensagem.attachments
    .map(anexo => anexo?.fallbackTitle || '')
    .filter(Boolean);
  return [{ ...primeiro, telefone: telefones[0] || '', telefones }];
};

// Cada contato com o número para "Conversar" e se leva as ações (resposta a pedido de
// contato não leva, como no cartão de um contato).
const comAcoes = (contato, mensagem) => ({
  ...contato,
  paraConversar: numeroParaConversar(
    contato.telefone,
    mensagem.contentAttributes
  ),
  comAcoes:
    Boolean(soDigitos(contato.telefone)) &&
    !mensagem.attachments?.[0]?.meta?.isContactInfoResponse,
});

// Os contatos do cartão: de uma mensagem só (vários anexos ou shared_contacts) ou do
// grupo de mensagens com o mesmo sourceId (um contato por mensagem).
export const contatosDoCartao = mensagens => {
  if (mensagens.length === 1) {
    const [mensagem] = mensagens;
    return contatosDoBalao(
      mensagem.attachments,
      mensagem.contentAttributes
    ).map(contato => comAcoes(contato, mensagem));
  }
  return mensagens.flatMap(mensagem =>
    contatosDeUmaMensagem(mensagem).map(contato => comAcoes(contato, mensagem))
  );
};
