// Roteiro do vídeo de trajeto do artigo 07.06 — "Horário de funcionamento,
// saudação e chamadas de voz". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/inboxMgmt.json (chave
// INBOX_MGMT.BUSINESS_HOURS.*) e no componente
// routes/dashboard/settings/inbox/components/{WeeklyAvailability,
// BusinessDay}.vue.
//
// O artigo junta três ajustes (horário, saudação, chamadas — este último só
// em WhatsApp Oficial). Não cabem os três com folga em 40s: o vídeo mostra
// só o primeiro (Horário de funcionamento — os 3 a 5 cliques que importam,
// como a regra permite para um "Como faz" longo); saudação e chamadas ficam
// só no texto do artigo.
//
// Trajeto: Configurações → Caixas de Entrada → a caixa → aba Horário de
// funcionamento → ligar a chave → marcar um dia (Segunda, com o horário
// padrão que a própria tela sugere ao marcar) → conferir o fuso horário →
// Atualizar configurações do horário comercial.
//
// "Atualizar" só grava working_hours/timezone na própria conta — sem
// chamada de fora — por isso o clique final acontece de verdade.

export const id = '07.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3005';

const NOME_CAIXA = 'Consultoria Zona Leste';

// Idempotente: recria a caixa do zero, sempre com horário desligado e
// nenhum dia marcado — é o "antes" que o vídeo precisa mostrar. Só mexe na
// caixa que este vídeo cria.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
nome = ${JSON.stringify(NOME_CAIXA)}
existente = conta.inboxes.find_by(name: nome)
existente&.destroy!
canal = Channel::Api.create!(account: conta, webhook_url: nil)
inbox = Inbox.create!(account: conta, name: nome, channel: canal, working_hours_enabled: false)
# O Inbox já nasce com dias padrão (terça a sexta abertos, 9h-17h) — sem
# isso o vídeo mostraria dias já marcados antes de qualquer clique, e o
# clique em Segunda (o dia que o vídeo marca) ficaria sem efeito visível.
# Fecha todos os 7 dias, pro "antes" ficar limpo de verdade.
inbox.working_hours.update_all(closed_all_day: true, open_hour: nil, open_minutes: nil, close_hour: nil, close_minutes: nil, open_all_day: false)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Definir o horário de funcionamento',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/inboxes/list`,
    aguardarTexto: NOME_CAIXA,
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Abra a caixa',
    acao: 'mover e clicar',
    alvo: {
      seletor: `div.flex.justify-between:has(span[title="${NOME_CAIXA}"]) a`,
    },
    zoom: 2,
    aguardarTextoDepois: 'Horário de funcionamento',
  },
  {
    legenda: 'Clique na aba Horário de funcionamento',
    acao: 'mover e clicar',
    alvo: { texto: 'Horário de funcionamento' },
    zoom: 2,
  },
  {
    legenda: 'Ligue a disponibilidade de negócios',
    acao: 'mover e clicar',
    alvo: { seletor: '.mx-6 button[role="switch"]' },
    zoom: 1.8,
  },
  {
    // Marca "Segunda" (2ª linha da tabela: dia 0=Domingo vem primeiro,
    // dia 1=Segunda em seguida) — ao marcar, a própria tela já sugere um
    // horário padrão válido (09:00–17:00), sem precisar abrir os campos de
    // hora.
    legenda: 'Marque os dias que funciona',
    acao: 'mover e clicar',
    alvo: { seletor: 'table tbody tr:nth-child(2) input[type="checkbox"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Confira o fuso horário certo',
    acao: 'parar',
    alvo: { texto: 'Selecionar fuso horário', blocoRolagem: 'start' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Clique em Atualizar',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar configurações do horário comercial' },
    zoom: 1.8,
    aguardarTextoDepois: 'Configurações de caixa de entrada atualizadas com sucesso',
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: 'Configurações de caixa de entrada atualizadas com sucesso' },
    zoom: 1.4,
    duracaoMs: 2200,
  },
];
