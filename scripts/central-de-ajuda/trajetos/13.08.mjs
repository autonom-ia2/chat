// Roteiro do vídeo de trajeto do artigo 13.08 — "Placeholders, teste e
// modelos de e-mail". Gravado em http://localhost:3005
// (EMAIL_CAMPAIGN_ENABLED=true).
//
// Cobre Placeholders e Enviar teste. "Escolher um modelo pronto" (galeria)
// ficou de fora por tempo. Para no formulário de "Enviar teste" preenchido
// e no de "Salvar como modelo" preenchido, sem clicar em Enviar nem em
// Salvar modelo — mesma regra dos outros vídeos de campanha (mesmo sem
// Sidekiq no ar para processar o envio de teste, a regra vale de
// qualquer jeito).
//
// Usa uma campanha própria (não a do 13.07): esta precisa de conteúdo já
// salvo e de destinatários com uma coluna extra, para a barra de
// Placeholders aparecer — o 13.07 precisa do oposto (campanha vazia, para
// a tela "Como você quer começar?" abrir). Guardamos os dois estados em
// campanhas separadas para os roteiros não conflitarem.

export const id = '13.08';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

const DOMINIO = 'desnorteada.test';
const CAMPANHA_NOME = 'Aviso de sinistro';
// ID estável entre gravações (find_or_initialize_by nunca apaga) —
// conferido em 2026-09-23.
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

const URL_EDITOR = `/app/accounts/${login.contaId}/campaigns/email_campaigns/${CAMPANHA_ID}/builder`;

export const cenas = [
  {
    legenda: 'Placeholders, teste e modelos de e-mail',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Abra o editor da campanha',
    acao: 'ir para',
    url: URL_EDITOR,
    aguardarTexto: 'Placeholders:',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique num campo para copiá-lo',
    acao: 'mover e clicar',
    alvo: { texto: '{{ plano }}' },
    zoom: 1.8,
  },
  {
    legenda: 'Vem das colunas da sua planilha',
    acao: 'parar',
    alvo: { texto: '{{ plano }}' },
    zoom: 1.6,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Enviar teste',
    acao: 'mover e clicar',
    alvo: { texto: 'Enviar teste' },
    zoom: 1.8,
  },
  {
    legenda: 'Digite o seu e-mail',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="nome@dominio.com"]' },
    texto: ['rafa-admin@desnorteada.test'],
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui — não envie',
    acao: 'parar',
    alvo: { texto: 'Enviar' },
    zoom: 1.6,
    duracaoMs: 1400,
  },
  {
    // Cancela em vez de navegar de novo pra mesma URL: pushState pra rota
    // idêntica não faz nada (nem fecha o diálogo aberto) — lição do 13.07.
    legenda: 'Cancele o envio de teste',
    acao: 'mover e clicar',
    alvo: { texto: 'Cancelar' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar como modelo',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar como modelo' },
    zoom: 1.8,
  },
  {
    legenda: 'Digite o nome do modelo',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: Convite para live"]' },
    texto: ['Renovação de seguro auto'],
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui — não salve ainda',
    acao: 'parar',
    alvo: { texto: 'Salvar modelo' },
    zoom: 1.6,
    duracaoMs: 1200,
  },
];
