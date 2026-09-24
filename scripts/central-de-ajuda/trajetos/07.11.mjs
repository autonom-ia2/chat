// Roteiro do vídeo de trajeto do artigo 07.11 — "Ligar a pesquisa de
// satisfação (CSAT) na caixa". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chave
// INBOX_MGMT.CSAT.*) e no componente
// routes/dashboard/settings/inbox/settingsPage/CustomerSatisfactionPage.vue.
//
// Trajeto: Configurações → Caixas de Entrada → a caixa → aba CSAT → ligar
// Habilitar CSAT → escolher Tipo de exibição (estrelas) → Atualizar.
//
// Caixa NÃO-WhatsApp de propósito: em caixa de WhatsApp, salvar CSAT cria
// de verdade um modelo e o envia para aprovação da Meta
// (createCSATTemplate) — serviço de fora, fora de escopo. Numa caixa
// comum (Channel::Api), "Atualizar" só grava csat_survey_enabled/
// csat_config na própria conta — sem chamada externa — por isso o clique
// final acontece de verdade.

export const id = '07.11';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_CAIXA = 'Site Consultoria Sul';

// Idempotente: recria a caixa do zero, sempre com CSAT desligado — é o
// "antes" que o vídeo precisa mostrar (ligar a chave em cena, não já
// ligada). Só mexe na caixa que este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA)}
existente = conta.inboxes.find_by(name: nome)
existente&.destroy!
canal = Channel::Api.create!(account: conta, webhook_url: nil)
Inbox.create!(account: conta, name: nome, channel: canal, csat_survey_enabled: false)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Ligar a pesquisa de satisfação (CSAT)',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: NOME_CAIXA,
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    // Mesma técnica de 07.03: o nome da caixa fica num <span title="...">
    // sem clique próprio; quem navega é o ícone/link da linha.
    legenda: 'Abra a caixa',
    acao: 'mover e clicar',
    alvo: {
      seletor: `div.flex.justify-between:has(span[title="${NOME_CAIXA}"]) a`,
    },
    zoom: 2,
    aguardarTextoDepois: 'CSAT',
  },
  {
    legenda: 'Clique na aba CSAT',
    acao: 'mover e clicar',
    alvo: { texto: 'CSAT' },
    zoom: 2,
  },
  {
    legenda: 'Ligue Habilitar CSAT',
    acao: 'mover e clicar',
    alvo: { seletor: '.mx-6 button[role="switch"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o Tipo de exibição',
    acao: 'mover e clicar',
    alvo: { seletor: 'button:has(i.i-ri-star-fill)' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar' },
    zoom: 1.8,
    aguardarTextoDepois: 'Configurações de CSAT atualizadas com sucesso',
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Configurações de CSAT atualizadas com sucesso' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
];
