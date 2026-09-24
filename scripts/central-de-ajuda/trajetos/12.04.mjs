// Roteiro do vídeo de trajeto do artigo 12.04 — "Criar e editar Respostas
// Prontas". Mesmo padrão do 12.03 (etiquetas): cria de verdade a resposta
// pronta "horario-atendimento" (atalho realista, não "teste") — o preparar
// apaga essa resposta antes de cada gravação para o clique em Enviar nunca
// esbarrar num atalho já existente (a API rejeita atalho duplicado).
//
// Seletores conferidos no código-fonte (AddCanned.vue,
// cannedMgmt.json ADD.FORM):
// - Atalho: `input[placeholder="Por favor, insira um atalho."]`.
// - Mensagem: editor rico, `.ProseMirror` (único na tela com o modal
//   aberto).
// - Botão salvar: "Enviar" (SUBMIT).
//
// Trajeto: Configurações → Respostas Prontas → Adicionar resposta pronta →
// preenche atalho e mensagem → Enviar.

export const id = '12.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

const ATALHO = 'horario-atendimento';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.canned_responses.where(short_code: ${JSON.stringify(ATALHO)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar e editar Respostas Prontas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra Configurações, Respostas Prontas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/canned-response/list`,
    aguardarTexto: 'Adicionar resposta pronta',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Adicionar resposta pronta',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar resposta pronta' },
    zoom: 1.6,
  },
  {
    legenda: 'Escreva o atalho',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Por favor, insira um atalho."]' },
    texto: [ATALHO],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a mensagem',
    acao: 'digitar',
    alvo: { seletor: '.ProseMirror' },
    texto: ['Atendemos de segunda a sábado, das 8h às 18h.'],
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Enviar',
    acao: 'mover e clicar',
    alvo: { texto: 'Enviar' },
    zoom: 1.6,
  },
  {
    legenda: 'Resposta pronta salva',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
