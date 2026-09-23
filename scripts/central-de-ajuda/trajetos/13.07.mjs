// Roteiro do vídeo de trajeto do artigo 13.07 — "Criar o e-mail com IA e
// montar no editor". Gravado em http://localhost:3005
// (EMAIL_CAMPAIGN_ENABLED=true, CRM_AI/CRM_COPILOT ligados pelo
// coordenador).
//
// Não dispara a geração por IA (regra do coordenador: "não dispare a
// geração por IA. Mostre o caminho e o editor"). Preenche o Briefing e
// para antes de clicar em "Gerar".
//
// Cobre só o caminho "Criar com IA" — a segunda metade do artigo (montar
// no editor de blocos) ficou de fora: testamos abrir uma segunda campanha
// em rascunho depois desta para mostrar "Começar do zero", mas navegar de
// um editor de campanha para outro (mesma rota, :campaignId diferente) via
// pushState não refaz o estado do componente — a tela "Como você quer
// começar?" não reaparece, nem passando por uma rota diferente no meio.
// Parece um bug real do componente (não reage à troca de parâmetro de
// rota), não algo que o roteiro consiga contornar. Marcar parcial, como
// combinado.
//
// Achado: a tela "Como você quer começar?" tem um bug de acentuação real
// no próprio produto (campaign.json → CAMPAIGN.EMAIL_CAMPAIGN.WELCOME):
// "Como voce quer comecar?", "Comecar com IA" — sem acento, também em
// produção, não é efeito do nosso ambiente. O vídeo grava a tela como ela
// realmente está.

export const id = '13.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3005';

const DOMINIO = 'desnorteada.test';
// Campanha em rascunho, sem conteúdo salvo, para a tela "Como você quer
// começar?" abrir sempre que a gente entrar no editor. ID estável entre
// gravações (find_or_initialize_by nunca apaga) — conferido em 2026-09-23.
const CAMPANHA_IA_NOME = 'Renovação de outubro';
const CAMPANHA_IA_ID = 2;
const BRIEFING =
  'E-mail de renovacao do seguro auto, tom amigavel, chamada para falar com o corretor';

// Roda antes de gravar: garante o domínio de envio verificado (sem passar
// pela verificação de verdade, que chama serviço de fora — só marcamos o
// registro como já verificado, igual fizemos para a caixa WhatsApp API do
// 13.03) e a campanha de e-mail em rascunho, sem conteúdo salvo.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
ident = EmailSenderIdentity.find_or_initialize_by(account: conta, domain: ${JSON.stringify(DOMINIO)})
ident.status = :verified
ident.verified_at ||= Time.current
ident.provider = "ses"
ident.from_email ||= "contato@desnorteada.test"
ident.save!(validate: false)

campanha = EmailCampaign.find_or_initialize_by(account: conta, name: ${JSON.stringify(CAMPANHA_IA_NOME)})
campanha.assign_attributes(
  from_name: "Corretora Desnorteada",
  from_email: "contato@desnorteada.test",
  reply_to: "atendimento@desnorteada.test",
  sender_identity_id: ident.id,
  status: :draft,
  body_html: nil,
  body_mjml: nil
)
campanha.save!(validate: false)
raise "id desatualizado: esperava ${CAMPANHA_IA_ID}, achou #{campanha.id}" unless campanha.id == ${CAMPANHA_IA_ID}
puts "preparo-ok"
`);
}

const URL_EDITOR_IA = `/app/accounts/${login.contaId}/campaigns/email_campaigns/${CAMPANHA_IA_ID}/builder`;

export const cenas = [
  {
    legenda: 'Criar e-mail com IA e montar no editor',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Abra o editor da campanha',
    acao: 'ir para',
    url: URL_EDITOR_IA,
    aguardarTexto: 'Como voce quer comecar?',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Clique em Comecar com IA',
    acao: 'mover e clicar',
    alvo: { texto: 'Comecar com IA' },
    zoom: 1.8,
  },
  {
    legenda: 'Descreva o e-mail no Briefing',
    acao: 'digitar',
    alvo: {
      seletor:
        'textarea[placeholder="Ex.: e-mail promocional sobre o novo plano de seguro auto, tom amigável, chamada para desconto"]',
    },
    texto: [BRIEFING],
    zoom: 1.8,
  },
  {
    legenda: 'Pare aqui — não gere',
    acao: 'parar',
    alvo: { texto: 'Gerar' },
    zoom: 1.6,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto — nada foi gerado',
    acao: 'parar',
    alvo: { texto: 'Gerar' },
    zoom: 1.6,
    duracaoMs: 1200,
  },
];
