// Roteiro do vídeo de trajeto do artigo 10.16 — "Trabalhar o CRM na
// conversa e tokens de integração". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (CRM_KANBAN.CONVERSATION,
// CRM_INTEGRATION_TOKENS) e em
// app/javascript/dashboard/routes/dashboard/conversation/ConversationAction.vue
// e CrmIntegrationTokensPage.vue.
//
// Duas partes: (1) criar o card do CRM a partir de uma conversa existente,
// sem card ainda; (2) criar um token de integração de exemplo.
//
// Regra do lote: o segredo do token aparece por inteiro na tela assim que
// é criado (caixa de revelação, uma vez só). A cena de "Pronto" NUNCA mira
// nessa caixa — mira a linha do token na lista de baixo (nome + status),
// que não mostra o segredo. O clique em "Criar token" remede o alvo DEPOIS
// do clique (mesmo botão, reposicionado mais abaixo pela caixa de
// revelação que nasce acima dele), então o recorte de "depois" já fica
// longe do segredo. O token é revogado no fim da gravação (fora do
// preparar — depois que o vídeo já existe), por segurança.

export const id = '10.16';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const CONVERSATION_ID = 2; // Joana Prado, WhatsApp Comercial — id interno (para o Crm::Card)
const CONVERSATION_DISPLAY_ID = 1; // mesma conversa — display_id (para a URL/rota)
const PIPELINE_NAME = 'Funil Comercial'; // meu, criado no 10.01 (P1)
const TOKEN_NAME = 'n8n produção comercial';

// Idempotente: garante que a conversa 2 ainda não tem card CRM (apaga só o
// card criado por ESTE vídeo, se sobrou de uma gravação anterior) e apaga
// qualquer token de integração com o mesmo nome de exemplo.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
Crm::Card.where(conversation_id: ${CONVERSATION_ID}).destroy_all
conta.crm_integration_tokens.where(name: ${JSON.stringify(TOKEN_NAME)}).destroy_all

# O painel direito da conversa (onde mora o bloco CRM) só aparece se a
# própria pessoa já tiver aberto ele antes — é um ui_setting por usuária,
# não algo global da conta. Liga aqui para a gravação sempre mostrar o
# painel, sem depender de estado deixado por uma sessão anterior.
usuaria = conta.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
config = (usuaria.ui_settings || {}).merge(
  "is_contact_sidebar_open" => true,
  "is_conv_actions_open" => true
)
usuaria.update!(ui_settings: config)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Trabalhar o CRM na conversa',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra a conversa',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/conversations/${CONVERSATION_DISPLAY_ID}`,
    aguardarTexto: 'CRM',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Veja o bloco CRM na conversa',
    acao: 'parar',
    alvo: { texto: 'Etapa atual' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Escolha o Funil',
    acao: 'selecionar',
    alvo: { seletor: 'div.grid.gap-2 > label:nth-child(1) select' },
    valor: PIPELINE_NAME,
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar card no CRM',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar card no CRM' },
    zoom: 1.8,
    aguardarTextoDepois: 'Card pronto no CRM',
  },
  {
    legenda: 'Abra Tokens de integração do CRM',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm/settings/integration-tokens`,
    aguardarTexto: 'Criar um token',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Escreva o nome do token',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: n8n produção"]' },
    texto: [TOKEN_NAME],
    zoom: 1.8,
  },
  {
    legenda: 'Marque Visualizar CRM',
    acao: 'mover e clicar',
    alvo: {
      seletor:
        'div.grid.grid-cols-1.gap-2.sm\\:grid-cols-2 > label:nth-child(1) input[type="checkbox"]',
    },
    zoom: 1.8,
  },
  {
    legenda: 'Marque Gerenciar cards',
    acao: 'mover e clicar',
    alvo: {
      seletor:
        'div.grid.grid-cols-1.gap-2.sm\\:grid-cols-2 > label:nth-child(2) input[type="checkbox"]',
    },
    zoom: 1.8,
  },
  {
    // Achado na 1ª gravação: com zoom 1,6 o recorte de "depois do clique"
    // (centrado no botão, remedido mais abaixo por causa da caixa de
    // revelação que nasce ACIMA dele) ainda alcançava a última linha do
    // segredo, que quebra em duas linhas. Zoom no teto do motor (2,5x)
    // encolhe o recorte o bastante para não alcançar mais essa linha —
    // conferido quadro a quadro depois da regravação: limpo.
    legenda: 'Clique em Criar token',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar token' },
    zoom: 2.5,
    aguardarTextoDepois: 'Tokens',
  },
  {
    // 2º achado: o botão "Dispensar" fica só ~40px (CSS) do texto do
    // segredo, dentro da mesma caixa — nenhum zoom até o teto do motor
    // (2,5x) separa os dois o bastante para excluir o segredo do recorte.
    // Por isso o vídeo NUNCA aproxima a câmera dessa caixa: sai da tela
    // (rota diferente) e volta para a mesma URL da lista de tokens, que
    // remonta o componente do zero — o segredo só existe no estado local
    // daquele componente, então a caixa de revelação já nasce fechada.
    legenda: 'Saia da tela de tokens',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm`,
    aguardarTexto: 'Seguro Auto',
    zoom: 1,
    duracaoMs: 600,
  },
  {
    legenda: 'Volte para os tokens de integração',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/crm/settings/integration-tokens`,
    aguardarTexto: TOKEN_NAME,
    zoom: 1,
    duracaoMs: 900,
  },
  {
    // Mira a linha da LISTA (nome + status) — essa linha nunca mostra o
    // segredo, e a caixa de revelação nem existe mais (componente
    // remontado do zero na navegação anterior).
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: TOKEN_NAME },
    zoom: 1.6,
    duracaoMs: 2200,
  },
];
