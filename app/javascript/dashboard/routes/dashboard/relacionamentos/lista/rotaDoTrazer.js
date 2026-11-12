import {
  CONTACT_IMPORT_ROUTE,
  isContactImportJourneyEnabled,
} from 'dashboard/routes/dashboard/contacts/import/contactImport.routes';
import { usarDemo } from '../fonte/modoDemo';

// #2947 — para onde o botão "Trazer minha lista" da lista leva. A tela nova
// (`relacionamentos_trazer`) só lê do servidor quando a E3 (#2896) entrar; até
// lá, fora da demonstração o botão leva à importação de contatos que já
// funciona. Sai junto com a E3, que liga a tela nova ao servidor.
const ROTA_DA_TELA_NOVA = 'relacionamentos_trazer';

export const rotaDoTrazer = demo =>
  demo ? ROTA_DA_TELA_NOVA : CONTACT_IMPORT_ROUTE;

// Onde a importação de contatos está desligada na instalação, o botão não tem
// para onde levar: some, em vez de cair na lista de contatos sem dizer nada.
export const temOndeTrazer = demo =>
  Boolean(demo) || isContactImportJourneyEnabled();

// Por link direto: fora da demonstração a tela nova ainda não tem o que mostrar,
// então a pessoa cai na importação (que, desligada, devolve para Contatos).
export const soNaDemonstracao = to =>
  usarDemo(to.query) ? true : { name: CONTACT_IMPORT_ROUTE, params: to.params };
