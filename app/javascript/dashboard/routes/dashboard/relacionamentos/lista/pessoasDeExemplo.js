import { DIA_EM_MS } from '../fonte/grupos';

// #2894 — a lista de exemplo da conta vazia: cinco pessoas inventadas, só para
// mostrar como a lista fica depois de trazer a planilha. Ninguém aqui existe;
// os telefones ficam no bloco fictício +55 11 9XXXX-00NN. `dias` é há quantos
// dias a pessoa "falou" (a data sai em segundos, como a API de contatos).
const EXEMPLOS = [
  { nome: 'Helena Quintanilha', fim: '71040011', dias: 0, cliente: true },
  { nome: 'Caio Pedrozani', fim: '82150012', dias: 1, cliente: false },
  { nome: 'Sueli Tavernaro', fim: '93260013', dias: 3, cliente: true },
  { nome: 'Jonas Albernaz', fim: '64370014', dias: 9, cliente: false },
  { nome: 'Priscila Montebelo', fim: '75480015', dias: 20, cliente: false },
];
const DDD_FICTICIO = '+55119';
const MS_EM_SEGUNDO = 1000;

export const pessoasDeExemplo = (agora = Date.now()) =>
  EXEMPLOS.map(({ nome, fim, dias, cliente }, indice) => ({
    id: `exemplo-${indice + 1}`,
    name: nome,
    phone_number: `${DDD_FICTICIO}${fim}`,
    contact_type: cliente ? 'customer' : 'lead',
    last_activity_at: Math.floor((agora - dias * DIA_EM_MS) / MS_EM_SEGUNDO),
  }));
