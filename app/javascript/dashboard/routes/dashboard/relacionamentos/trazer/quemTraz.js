// #2896 — quem pode "Trazer minha lista": a mesma regra da importação de
// contatos de hoje (contacts/import/contactImport.routes.js) e do servidor
// (ContactPolicy#import?). Vale para a rota e para o botão da lista; esconder é
// só conforto, quem decide de verdade é o servidor.
export const QUEM_TRAZ_LISTA = ['administrator', 'contact_manage'];
