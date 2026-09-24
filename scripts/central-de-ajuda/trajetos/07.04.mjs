// Roteiro do vídeo de trajeto do artigo 07.04 — "Saúde da conta e aba
// Configuração". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chaves
// INBOX_MGMT.TABS.*, INBOX_MGMT.ACCOUNT_HEALTH.* e
// INBOX_MGMT.SETTINGS_POPUP.WHATSAPP_*) e nos componentes
// routes/dashboard/settings/inbox/components/AccountHealth.vue e
// routes/dashboard/settings/inbox/settingsPage/ConfigurationPage.vue.
//
// As duas abas do artigo (Saúde da conta, Configuração) só existem para
// canal WhatsApp Oficial pela Cloud (provider "whatsapp_cloud") — é o único
// canal deste vídeo que precisa desse provider, ao contrário dos outros
// roteiros do lote (07.02/07.05/07.08 usam "default" de propósito). Duas
// proteções contra chamada de fora, as duas confirmadas lendo o código:
//
// 1. `after_commit :setup_webhooks, on: :create, if: :should_auto_setup_webhooks?`
//    (app/models/channel/whatsapp.rb) registraria um webhook de verdade na
//    Meta ao criar o canal — `should_auto_setup_webhooks?` só é false para
//    `provider_config["source"] == "manual_setup_v2"` (ou "embedded_signup").
//    O preparo usa esse source de propósito, e também pula o callback
//    `sync_templates` (delega pra Whatsapp::Providers::WhatsappCloudService,
//    que chama a Graph API pra buscar modelos) com `skip_callback`, mesma
//    técnica já usada em 07.05.
// 2. A aba "Saúde da conta" chama de verdade `Whatsapp::HealthService#
//    sync_health_status!` (Settings.vue, watch em `inbox`, roda ao abrir
//    QUALQUER aba, não só a de saúde) — mas o serviço só bate na Graph API
//    depois de `validate_channel!` confirmar api_key, phone_number_id e
//    business_account_id preenchidos (app/services/whatsapp/health_service.rb).
//    O preparo deixa os três em branco de propósito: a checagem falha local,
//    sem nenhuma requisição de rede, e a tela mostra o card de erro genérico
//    — que é exatamente o estado real que o artigo descreve em "O que dá
//    errado": "Aparece 'Dados de saúde não estão disponíveis'".
//
// "Sincronizar Modelos" e o "Atualizar" da chave de API (que revalida a
// credencial contra a Meta) nunca são clicados — só preenchidos/destacados.

export const id = '07.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_CAIXA = 'WhatsApp Oficial Regional';
const TELEFONE_CANAL = '5511900000488';

// Idempotente: recria o canal do zero a cada gravação. Só mexe na caixa que
// este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA)}
telefone = ${JSON.stringify(TELEFONE_CANAL)}

existente = conta.inboxes.find_by(name: nome)
existente&.destroy!
Channel::Whatsapp.where(phone_number: telefone).destroy_all

Channel::Whatsapp.skip_callback(:create, :after, :sync_templates, raise: false)
canal = Channel::Whatsapp.new(
  account: conta,
  phone_number: telefone,
  provider: "whatsapp_cloud",
  # "manual_setup_v2" desliga o auto-setup de webhook (should_auto_setup_webhooks?)
  # — sem isso o after_commit ligaria de verdade pra Meta ao criar. De
  # propósito SEM api_key/phone_number_id/business_account_id: a aba Saúde
  # da conta falha local (sem rede) por causa disso, não por falha de fato.
  provider_config: { "source" => "manual_setup_v2" }
)
canal.save!(validate: false)
Inbox.create!(account: conta, name: nome, channel: canal)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Saúde da conta e aba Configuração',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: NOME_CAIXA,
    zoom: 1,
    duracaoMs: 2000,
  },
  {
    legenda: 'Abra a caixa de WhatsApp Oficial',
    acao: 'mover e clicar',
    alvo: {
      seletor: `div.flex.justify-between:has(span[title="${NOME_CAIXA}"]) a`,
    },
    zoom: 2,
    aguardarTextoDepois: 'Saúde da conta',
  },
  {
    legenda: 'Clique na aba Saúde da conta',
    acao: 'mover e clicar',
    alvo: { texto: 'Saúde da conta' },
    zoom: 2,
    aguardarTextoDepois: 'não estão disponíveis',
  },
  {
    // Estado real quando a chave não responde à Meta — o mesmo que o
    // artigo descreve em "O que dá errado".
    legenda: 'Sem chave, mostra o aviso da Meta',
    acao: 'parar',
    alvo: { texto: 'Os dados da saúde do WhatsApp não estão disponíveis' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
  {
    legenda: 'Clique na aba Configuração',
    acao: 'mover e clicar',
    alvo: { texto: 'Configuração' },
    zoom: 2,
  },
  {
    legenda: 'Preencha a chave nova, sem enviar',
    acao: 'digitar',
    alvo: {
      seletor: 'input[placeholder="Digite a nova chave de API aqui"]',
    },
    texto: ['EXEMPLOchaveAPI000111222333'],
    zoom: 1.8,
  },
  {
    // Fecho: mostra "Sincronizar Modelos" em destaque, sem clicar — chama a
    // Graph API de verdade.
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Sincronizar Modelos' },
    zoom: 1.8,
    duracaoMs: 2400,
  },
];
