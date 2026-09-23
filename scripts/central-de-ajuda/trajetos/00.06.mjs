// Roteiro do vídeo de trajeto do artigo 00.06 — "Passo 5 — Montar o
// primeiro funil". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (CRM_KANBAN.ACTIONS,
// CRM_KANBAN.PIPELINE_DRAWER, CRM_KANBAN.INBOX_SETTINGS).
//
// Trajeto: CRM Kanban → Novo funil → nome → Criar funil → Configurar
// inboxes → CRM ativo na caixa → Funil padrão → Salvar.
//
// Isolamento entre agentes: cria um funil PRÓPRIO ("Seguro Residencial") e
// liga só a caixa "Suporte Demo (janela)" (nenhum outro vídeo desta lista
// mexe nela) — não toca nos funis nem nas ligações de inbox que já existem
// na conta de teste.

export const id = '00.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_FUNIL = 'Seguro Residencial';
// Caixa fixa da conta de teste (id 11). Buscada pelo id no preparar porque
// o nome é dado fictício compartilhado entre vídeos e já mudou de nome
// nesta mesma conta (outro agente renomeou de "Suporte Demo (janela)" para
// este) — o id não muda.
const ID_INBOX = 11;
const NOME_INBOX = 'WhatsApp Pós-venda';

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
usuaria = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria

nome_funil = ${JSON.stringify(NOME_FUNIL)}
antigo = account.crm_pipelines.find_by(name: nome_funil)
if antigo
  Crm::PipelineInbox.where(pipeline_id: antigo.id).destroy_all
  antigo.cards.destroy_all
  antigo.destroy
end

inbox = account.inboxes.find_by(id: ${ID_INBOX})
raise "inbox id ${ID_INBOX} não encontrada" unless inbox
puts "preparo-ok inbox_nome=#{inbox.name}"
`);
}

export const cenas = [
  {
    legenda: 'Montar o primeiro funil',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra o CRM Kanban',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm`,
    aguardarTexto: 'Novo funil',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Novo funil',
    acao: 'mover e clicar',
    alvo: { texto: 'Novo funil' },
    aguardarTextoDepois: 'Nome do funil',
    zoom: 1.6,
  },
  {
    legenda: 'Escolha o nome do funil',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: Vendas, Pós-venda, Renovações"]' },
    // O campo já nasce preenchido com "Funil Comercial" (nome padrão do
    // formulário) — limpa antes de escrever o nome deste funil.
    limparAntes: true,
    texto: [NOME_FUNIL],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar funil',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar funil' },
    aguardarTextoDepois: NOME_FUNIL,
    zoom: 1.6,
  },
  {
    // Pausa curta: o toast "Funil criado" e a transição de fechamento do
    // drawer anterior ainda podem estar cobrindo a barra de ações por
    // alguns instantes — clicar em cima demais cedo acerta esse overlay,
    // não o botão.
    legenda: 'Funil criado',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Configurar inboxes',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurar inboxes' },
    aguardarTextoDepois: 'CRM ativo',
    zoom: 1.6,
  },
  {
    legenda: 'Marque CRM ativo na caixa',
    acao: 'mover e clicar',
    alvo: {
      texto: 'CRM ativo',
      dentro: { texto: NOME_INBOX, subindoAte: 'section' },
    },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o Funil padrão',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Sem funil padrão',
      dentro: { texto: NOME_INBOX, subindoAte: 'section' },
    },
    aguardarTextoDepois: NOME_FUNIL,
    zoom: 1.8,
  },
  {
    // A lista de opções do combobox aparece uma única vez na tela (o nome
    // do funil que acabou de ser criado não se repete em outro lugar), por
    // isso não precisa do escopo "dentro" aqui.
    legenda: 'Clique no nome do funil',
    acao: 'mover e clicar',
    alvo: { texto: NOME_FUNIL },
    zoom: 1.8,
  },
  {
    legenda: 'Marque Criar card automaticamente e salve',
    acao: 'mover e clicar',
    alvo: {
      texto: 'Salvar',
      dentro: { texto: NOME_INBOX, subindoAte: 'section' },
    },
    aguardarTextoDepois: 'Salvo',
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
