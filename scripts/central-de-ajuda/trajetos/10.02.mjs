// Roteiro do vídeo de trajeto do artigo 10.02 — "Ler o quadro Kanban e criar
// um card na mão". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json e em
// app/javascript/dashboard/routes/dashboard/crm/components/CrmCardDrawer.vue.
//
// Trajeto: barra lateral → CRM → Kanban → Novo card → Título → Criar card.
// O botão "Criar card" usa o mesmo ícone de confirmação (i-lucide-check) que
// os outros drawers do CRM — clicar por esse ícone, não pelo texto do botão,
// porque o texto fica embaixo da bolha flutuante "Guia da Plataforma" (canto
// inferior direito, achado na gravação do 10.01). Em modo de criação (card
// novo) não há nenhum outro botão com esse ícone na tela, então o seletor é
// único.

export const id = '10.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

// "Seguro auto — Carla Mendes" é o título fictício deste vídeo (nome de
// oportunidade real de corretora, não um rótulo genérico) — apaga antes de
// gravar de novo, só o card SEM contato/conversa vinculados (o nosso,
// criado na mão), nunca um card de verdade. Também limpa o título antigo
// "Ligar para confirmar orçamento", da primeira versão deste vídeo.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_cards
  .where(title: ["Seguro auto — Carla Mendes", "Ligar para confirmar orçamento"], contact_id: nil, conversation_id: nil)
  .destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ler o quadro e criar um card',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra CRM no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'CRM' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Kanban',
    acao: 'mover e clicar',
    alvo: { texto: 'Kanban' },
    zoom: 1.8,
  },
  {
    legenda: 'Veja as colunas do funil',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Novo card',
    acao: 'mover e clicar',
    alvo: { texto: 'Novo card' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o Título',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Nome da oportunidade"]' },
    texto: ['Seguro auto — Carla Mendes'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar card',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-lucide-check"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
