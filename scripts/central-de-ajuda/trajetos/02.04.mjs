// Roteiro do vídeo de trajeto do artigo 02.04 — "Sua assinatura de
// mensagens". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{settings,conversation}.json.
//
// Trajeto: foto no rodapé da barra lateral → Configurações do Perfil →
// Assinatura de mensagens pessoais → escrever → Salvar assinatura da
// mensagem → abrir a conversa 1 → ícone de assinatura na caixa de resposta.

export const id = '02.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Roda antes de começar a gravar (não entra no vídeo). Garante que a
// assinatura comece desligada no canal usado na cena final, senão o fim do
// vídeo não mostraria a ativação — e garante que o campo de assinatura
// comece vazio, para a cena de digitação ficar limpa.
export async function preparar({ rodarRails }) {
  await rodarRails(`
usuaria = Account.find(${login.contaId}).users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
usuaria.update!(message_signature: nil)
# A conversa 1 usa o canal da inbox "WhatsApp Comercial", que neste dado de
# teste é um Channel::Api (não um Channel::Whatsapp de verdade) — a chave da
# flag de assinatura segue o channel_type real, não o nome da inbox.
config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

const ASSINATURA = ['Att, Rita', 'Corretora Desnorteada'];

export const cenas = [
  {
    legenda: 'Salvar sua assinatura de mensagens',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2700,
  },
  {
    legenda: 'Clique na sua foto',
    acao: 'mover e clicar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Configurações do Perfil',
    acao: 'mover e clicar',
    alvo: { texto: 'Configurações do Perfil' },
    // Zoom mais fechado que o padrão: o clique dispara navegação de página
    // inteira, e a pausa de 0,8s depois do clique já mostra a tela de
    // destino — um recorte largo alcançaria o conteúdo principal da direita
    // (que tem texto de marca). Fechado assim, o recorte fica contido na
    // barra lateral em antes e depois do clique.
    zoom: 2.6,
  },
  {
    legenda: 'Vá até Assinatura de mensagens pessoais',
    acao: 'parar',
    // blocoRolagem: 'start' bota o título no alto do recorte em vez de no
    // centro — a seção "Interface" (com texto de marca) fica logo ACIMA
    // desta, e "center" deixava um pedaço dela dentro do recorte.
    alvo: { texto: 'Assinatura de mensagens pessoais', blocoRolagem: 'start' },
    zoom: 1.5,
    duracaoMs: 1400,
  },
  {
    legenda: 'Escreva sua assinatura',
    acao: 'digitar',
    alvo: { seletor: '#message-signature-input .ProseMirror' },
    texto: ASSINATURA,
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar assinatura da mensagem',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar assinatura da mensagem' },
    zoom: 1.6,
  },
  {
    legenda: 'Assinatura salva',
    acao: 'parar',
    alvo: { texto: 'Assinatura salva com sucesso' },
    zoom: 1.3,
    duracaoMs: 1600,
  },
  {
    legenda: 'Abra uma conversa',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/conversations/1`,
    // Sem isso a cena corta enquanto a lista ainda mostra "Carregando
    // conversas" — só fecha quando a mensagem de verdade está na tela.
    aguardarTexto: 'Quero cotar seguro do meu carro',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Ative a assinatura para este canal',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-ph-signature' },
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2700,
  },
];
