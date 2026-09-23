// Roteiro do vídeo de trajeto do artigo 13.09 — "Destinatários, envio e
// gestão da campanha de e-mail". Gravado em http://localhost:3005
// (EMAIL_CAMPAIGN_ENABLED=true).
//
// Cobre a tela Destinatários (verificação pré-envio, lista) e o começo do
// agendamento — para antes de clicar em "Agendar" (o botão que confirma) e
// nunca clica em "Enviar agora". Subir CSV/XLSX de destinatários fica de
// fora (mesmo limite de upload do 13.04/13.06); os destinatários usados
// aqui vêm do preparo do 13.08 (mesma campanha "Aviso de sinistro").
// Gerir depois de criada (Pausar/Retomar/Cancelar/Duplicar/Excluir) também
// ficou de fora — são ações repetitivas de botão simples, e o artigo já
// cobre bem sozinho.

export const id = '13.09';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

const DOMINIO = 'desnorteada.test';
const CAMPANHA_NOME = 'Aviso de sinistro';
// Mesma campanha do 13.08 — ID estável entre gravações. Conferido em
// 2026-09-23.
const CAMPANHA_ID = 3;

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
ident = EmailSenderIdentity.find_or_initialize_by(account: conta, domain: ${JSON.stringify(DOMINIO)})
ident.status = :verified
ident.verified_at ||= Time.current
ident.provider = "ses"
ident.from_email ||= "contato@desnorteada.test"
ident.save!(validate: false)

campanha = EmailCampaign.find_or_initialize_by(account: conta, name: ${JSON.stringify(CAMPANHA_NOME)})
mjml = "<mjml><mj-body><mj-section><mj-column><mj-text>Ola {{ nome }}, sua apolice vence em breve.</mj-text></mj-column></mj-section></mj-body></mjml>"
campanha.assign_attributes(
  from_name: "Corretora Desnorteada",
  from_email: "contato@desnorteada.test",
  reply_to: "atendimento@desnorteada.test",
  sender_identity_id: ident.id,
  status: :draft,
  subject: "Sua apolice esta perto de vencer",
  body_html: "<p>Ola {{ nome }}, sua apolice vence em breve.</p>",
  body_mjml: mjml
)
campanha.save!(validate: false)
raise "id desatualizado: esperava ${CAMPANHA_ID}, achou #{campanha.id}" unless campanha.id == ${CAMPANHA_ID}

[["Carla Mendes", "carla-mendes@desnorteada.test", {"plano" => "Seguro Auto Completo"}],
 ["Fabio Nogueira", "fabio-nogueira@desnorteada.test", {"plano" => "Seguro Auto Basico"}]].each do |nome, email, custom|
  r = campanha.email_campaign_recipients.find_or_initialize_by(email: email)
  r.name = nome
  r.custom_data = custom
  r.save!(validate: false)
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Destinatários, envio e gestão da campanha',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Abra o menu Campanhas',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Campaigns"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Abra Campanhas de e-mail',
    acao: 'mover e clicar',
    alvo: { texto: 'Campanhas de e-mail' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Destinatários, no card',
    acao: 'mover e clicar',
    // "Destinatários" repete em cada card da lista — o motor pega o
    // primeiro em ordem do documento, que é o card "Aviso de sinistro"
    // (conferido ao vivo).
    alvo: { texto: 'Destinatários' },
    zoom: 1.8,
  },
  {
    legenda: 'Confira a verificação pré-envio',
    acao: 'parar',
    alvo: {
      texto:
        'Todos os campos de personalização usados nesta campanha têm valores. Pronto para enviar.',
    },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Ou clique em Agendar',
    acao: 'mover e clicar',
    alvo: { texto: 'Agendar' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha data e hora',
    acao: 'parar',
    alvo: { seletor: 'input[type="datetime-local"]' },
    zoom: 1.6,
    duracaoMs: 1200,
  },
  {
    legenda: 'Pare aqui — não agende nem envie',
    acao: 'parar',
    alvo: { seletor: 'input[type="datetime-local"]' },
    zoom: 1.6,
    duracaoMs: 1200,
  },
];
