import { CONTACT_IMPORT_ROUTE } from 'dashboard/routes/dashboard/contacts/import/contactImport.routes';

// #2947 — para onde o botão "Trazer minha lista" da lista leva. A tela nova
// (`relacionamentos_trazer`) só lê do servidor quando a E3 (#2896) entrar; até
// lá, fora da demonstração o botão leva à importação de contatos que já
// funciona. Sai junto com a E3, que liga a tela nova ao servidor.
export const rotaDoTrazer = demo =>
  demo ? 'relacionamentos_trazer' : CONTACT_IMPORT_ROUTE;
