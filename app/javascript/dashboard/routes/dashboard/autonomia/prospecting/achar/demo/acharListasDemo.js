// #2775 — dados da demonstração das listas (F6). Tudo inventado: empresas,
// pessoas e números não existem. Só é carregado no ambiente de
// desenvolvimento (acharFonteListas.js, `import.meta.env.DEV`). No formato da
// API (audiences), para passar pelos mesmos tradutores da fonte.

// A primeira pode receber mais empresas; a segunda já foi usada numa campanha
// enviada e só oferece "Criar uma cópia para editar".
export const LISTAS = [
  {
    id: 301,
    name: 'Padarias · Centro',
    companies: 12,
    whatsapp: 9,
    email: 5,
    in_crm: 3,
    locked: false,
  },
  {
    id: 302,
    name: 'Oficinas · Barão Geraldo',
    companies: 8,
    whatsapp: 6,
    email: 2,
    in_crm: 1,
    locked: true,
  },
];

export const COPIA_ID = 303;

const MEMBRO = (linha, nome, empresa, extra = {}) => ({
  contact_id: 900 + linha,
  row_number: linha,
  name: nome,
  company_name: empresa,
  whatsapp: true,
  email: false,
  in_crm: false,
  lead_id: linha,
  ...extra,
});

export const MEMBROS = [
  MEMBRO(1, 'Marta Ribeiro', 'Padaria Pão da Praça', {
    email: true,
    in_crm: true,
  }),
  MEMBRO(2, 'Padaria Doce Esquina', 'Padaria Doce Esquina'),
  MEMBRO(3, 'Jorge Alencar', 'Panificadora Trigo Bom', { email: true }),
  MEMBRO(4, 'Padaria Flor do Trigo', 'Padaria Flor do Trigo', {
    in_crm: true,
  }),
  MEMBRO(5, 'Lúcia Prado', 'Confeitaria Massa Leve', {
    whatsapp: false,
    email: true,
  }),
];

// A gaveta da empresa: ela está na primeira lista.
export const LISTAS_DA_EMPRESA = [
  { id: 301, nome: 'Padarias · Centro', enviada: false },
];
