// Roteiro do vídeo de trajeto do artigo 08.05 — "Cabeçalho, resposta e
// assinatura na conversa". Seletores conferidos no DOM renderizado (login
// manual de exploração):
// - botão do número da conversa: `.conversation--header--actions button`
//   (app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue:150,
//   único botão dentro do bloco de ações do cabeçalho — o texto muda por
//   conversa, "#2", "#5" etc., por isso o alvo usa a classe, não o texto).
// - editor da resposta: `.ProseMirror` (único editor renderizado na aba
//   Responder).
// - ícone de assinatura: `.i-ph-signature` (mesmo seletor do roteiro
//   02.04).
// Todas as conversas de teste desta conta usam Channel::Api, então a mesma
// chave de ui_settings ("channel_api_signature_enabled") vale para
// qualquer uma delas.
//
// Trajeto: tela de Conversas → aba Todos → abre um card qualquer → clique
// no # do cabeçalho → escreve uma resposta → clique no ícone de assinatura.
// Não envia a mensagem (só demonstra a digitação, sem criar dado na conta).

export const id = '08.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
usuaria = Account.find(${login.contaId}).users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
usuaria.update!(message_signature: "Att, Lia\\nCorretora Desnorteada")
config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

const RESPOSTA = ['Claro, posso te ajudar com isso agora.'];

export const cenas = [
  {
    legenda: 'Cabeçalho, resposta e assinatura',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique na aba Todos',
    acao: 'mover e clicar',
    alvo: { seletor: 'li:nth-child(3) > a.text-button' },
    zoom: 1.5,
  },
  {
    legenda: 'Abra uma conversa qualquer',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique no # da conversa',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation--header--actions button' },
    zoom: 1.8,
  },
  {
    legenda: 'Número copiado',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1400,
  },
  {
    legenda: 'Escreva a resposta ao cliente',
    acao: 'digitar',
    alvo: { seletor: '.ProseMirror' },
    texto: RESPOSTA,
    zoom: 1.6,
  },
  {
    legenda: 'Clique no ícone de assinatura',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-ph-signature' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
