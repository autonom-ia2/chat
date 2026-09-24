// Roteiro do vídeo de trajeto do artigo 03.02 — "Segurança da conta: SAML
// SSO". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json (SECURITY_SETTINGS.SAML).
//
// Achado (bloqueador, não é bug do vídeo): nos três servidores deste lote a
// tela de Segurança mostrava um PAYWALL de upsell em vez do formulário —
// não a mensagem de "SAML desativado" que o artigo documenta. Causa raiz:
// `InstallationConfig.INSTALLATION_PRICING_PLAN` estava em "community"
// (`lib/chatwoot_hub.rb:39`), o que zera duas coisas ao mesmo tempo:
// `allowed_login_methods` no controller (tira "saml" da lista, então
// `isSamlSsoEnabled` fica falso) e `enterprisePlanName` no front (então
// `hasPremiumEnterprise` fica falso e `shouldShowPaywall('saml')` fica
// true — o `<SamlPaywall v-if>` entra ANTES do `v-else-if` que mostraria o
// formulário, ver Index.vue). A flag de CONTA "saml" já estava ligada
// (confirmado via rails runner) — o bloqueio nunca foi por conta, foi por
// esse valor de instalação.
//
// `preparar` ajusta esse InstallationConfig para "enterprise" — ESCOPO
// GLOBAL, não só da conta 9: vale para os três servidores Rails do lote
// (mesmo banco). Reportado com destaque na entrega, como pedem as
// instruções, para o Rodrigo decidir se reverte.
//
// Trajeto: Configurações → Segurança → ligar a chave SAML SSO → preencher
// SSO URL, ID da Entidade e Certificado com dados fictícios → NÃO clicar em
// Atualizar configurações de SAML (regra do lote: formulário que só falta
// enviar fica parado no preenchido).

export const id = '03.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3005';

const SSO_URL = 'https://sso.desnorteada.test/saml/sso';
const IDP_ENTITY_ID = 'https://sso.desnorteada.test/saml';
const CERTIFICADO = [
  '-----BEGIN CERTIFICATE-----',
  'EXEMPLODECERTIFICADODESNORTEADASOMENTEPARADEMONSTRACAO',
  '-----END CERTIFICATE-----',
];

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})

# Ajuste de INSTALAÇÃO (não é flag de conta) — sem isso a tela mostra um
# paywall de upsell em vez do formulário de SAML, nos três servidores do
# lote. Idempotente.
config = InstallationConfig.find_or_create_by!(name: "INSTALLATION_PRICING_PLAN") do |c|
  c.value = "enterprise"
end
config.update!(value: "enterprise") if config.value != "enterprise"

# A conta começa sem configuração de SAML salva: a chave nasce desligada e
# os campos vazios, para o vídeo mostrar o "antes" real.
AccountSamlSettings.where(account_id: account.id).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Configurar o SAML SSO da conta',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Abra Configurações, Segurança',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/security`,
    aguardarTexto: 'SAML SSO',
    zoom: 1.3,
    duracaoMs: 1200,
  },
  {
    legenda: 'Ligue a chave do SAML SSO',
    acao: 'mover e clicar',
    alvo: { seletor: 'button[role="switch"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Preencha a SSO URL',
    acao: 'digitar',
    alvo: { seletor: 'input[type="url"]' },
    texto: [SSO_URL],
    zoom: 1.8,
  },
  {
    legenda: 'Preencha o ID da Entidade',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="https://sso.example.com/saml"]' },
    texto: [IDP_ENTITY_ID],
    zoom: 1.8,
  },
  {
    legenda: 'Cole o Certificado de assinatura',
    acao: 'digitar',
    alvo: {
      seletor: 'textarea[placeholder^="-----BEGIN CERTIFICATE"]',
    },
    texto: CERTIFICADO,
    zoom: 1.8,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2600,
  },
];
