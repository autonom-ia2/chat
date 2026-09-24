// Roteiro do vídeo de trajeto do artigo 08.08 — "Anexar arquivo e gravar
// áudio". Anexa de verdade um PDF fictício ("Proposta-seguro-auto.pdf",
// criado no $TMPDIR pelo teste, sem nada de cliente real) numa conversa
// PRÓPRIA deste vídeo. NÃO envia a mensagem — regra do Rodrigo para este
// vídeo, além de já valer para todo vídeo desta leva.
//
// Gravação de áudio precisa de microfone de verdade, que o Chrome headless
// não tem — o vídeo só mostra o botão (ícone `.i-ph-microphone`), sem
// clicar. O passo 3-4 do artigo (gravar e enviar áudio) fica só no texto.
//
// Seletores conferidos no código-fonte
// (components/widgets/WootWriter/ReplyBottomPanel.vue):
// - anexar: ícone `.i-ph-paperclip`, dentro do componente FileUpload que
//   embrulha um `<input id="conversationAttachment" type="file">` real —
//   é nesse input que `anexarArquivo` usa DOM.setFileInputFiles.
// - áudio: ícone `.i-ph-microphone`.
//
// Trajeto: conversa própria → clique no clipe → anexa o PDF → aguarda a
// prévia do anexo → mostra o ícone de microfone → para, sem enviar.

import { join } from 'node:path';

export const id = '08.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

const PASTA_TMP = process.env.TMPDIR || '/tmp';
const ARQUIVO_PDF = join(PASTA_TMP, 'Proposta-seguro-auto.pdf');

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
inbox = conta.inboxes.find_by!(name: "WhatsApp Comercial")
contato = conta.contacts.find_or_create_by!(name: "Ricardo Nunes") do |c|
  c.email = "ricardo-nunes@cliente.test"
  c.phone_number = "+5511990000033"
end
cic = contato.contact_inboxes.find_or_create_by!(inbox: inbox) do |ci|
  ci.source_id = SecureRandom.uuid
end
conversa = conta.conversations.find_by(contact_id: contato.id, inbox_id: inbox.id)
if conversa.nil?
  conversa = conta.conversations.create!(contact: contato, inbox: inbox, contact_inbox: cic, status: :open)
end
conversa.update!(status: :open)
conversa.messages.where(message_type: :incoming).first ||
  conversa.messages.create!(content: "Posso mandar os documentos da proposta por aqui?", message_type: :incoming, account: conta, inbox: inbox, sender: contato)
conversa.update_columns(last_activity_at: Time.current)

usuaria = conta.users.find_by!(name: ${JSON.stringify(login.usuarioNome)})
config = (usuaria.ui_settings || {}).merge("channel_api_signature_enabled" => false)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Anexar arquivo e gravar áudio',
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
    legenda: 'Abra sua conversa',
    acao: 'mover e clicar',
    alvo: { seletor: '.conversation' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique no ícone de clipe',
    acao: 'anexarArquivo',
    alvo: { seletor: '.i-ph-paperclip' },
    seletorArquivo: '#conversationAttachment',
    arquivo: ARQUIVO_PDF,
    zoom: 1.8,
    pausaDepoisMs: 1600,
  },
  {
    legenda: 'Aguarde o envio terminar',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2000,
  },
  {
    // "passar o mouse" (não "parar"): move o cursor de verdade até o
    // ícone — um "parar" deixa o cursor onde a cena anterior largou (no
    // clipe), e a diferença visual entre as duas cenas fica pequena demais
    // pra mostrar qual botão é o do áudio. NÃO clica: microfone precisa de
    // hardware de verdade, que o Chrome headless não tem.
    legenda: 'Para gravar áudio, use o microfone',
    acao: 'passar o mouse',
    alvo: { seletor: '.i-ph-microphone' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 2200,
  },
];
