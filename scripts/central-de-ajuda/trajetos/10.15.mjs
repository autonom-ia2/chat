// Roteiro do vídeo de trajeto do artigo 10.15 — "SLA do CRM: políticas e
// calendários". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/crm.json (CRM_SLA.*) e em
// app/javascript/dashboard/routes/dashboard/crm/components/sla/
// CrmSlaPolicyDialog.vue e CrmScheduleEditor.vue.
//
// Trajeto: CRM → SLA → Nova política → nome + meta de primeira resposta →
// Salvar → Calendários de atendimento → Editar calendário → ligar um dia →
// Salvar calendário.

export const id = '10.15';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

const POLICY_NAME = 'Atendimento comercial Sul';

// Idempotente: apaga a política anterior com esse nome exato antes de
// recriar. Não mexe em nenhuma outra política nem em calendário de outra
// caixa além da usada na cena (WhatsApp Comercial).
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.sla_policies.where(name: ${JSON.stringify(POLICY_NAME)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar uma política de SLA',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    legenda: 'Abra CRM no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'CRM' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em SLA',
    acao: 'mover e clicar',
    alvo: { texto: 'SLA' },
    zoom: 1.8,
    aguardarTextoDepois: 'Políticas',
  },
  {
    legenda: 'Clique em Nova política',
    acao: 'mover e clicar',
    alvo: { texto: 'Nova política' },
    zoom: 1.8,
  },
  {
    legenda: 'Escreva o nome da política',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: Suporte prioritário"]' },
    texto: [POLICY_NAME],
    zoom: 1.8,
  },
  {
    legenda: 'Defina o tempo de primeira resposta',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="ex.: 30"]' },
    texto: ['20'],
    zoom: 1.8,
  },
  {
    // Achado na 1ª gravação: "Próxima resposta" também nasce ligada, sem
    // valor — isso deixa a política inválida (Salvar fica desabilitado)
    // mesmo com o nome e a 1ª resposta preenchidos. Desliga essa meta em
    // vez de preencher um 2º campo com o mesmo placeholder da 1ª resposta.
    legenda: 'Desligue Tempo de próxima resposta',
    acao: 'mover e clicar',
    alvo: {
      seletor:
        '.grid.gap-2.rounded-xl.border.border-n-weak > div.grid.gap-1:nth-of-type(2) button[role="switch"]',
    },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar' },
    zoom: 1.6,
    aguardarTextoDepois: POLICY_NAME,
  },
  {
    // O botão é só ícone (tooltip "Editar calendário", sem texto visível)
    // — a WhatsApp Comercial é a 1ª linha da tabela.
    legenda: 'Clique em Editar calendário',
    acao: 'mover e clicar',
    alvo: { seletor: 'tbody tr:nth-child(1) span[class*="i-lucide-calendar-cog"]' },
    zoom: 1.6,
  },
  {
    legenda: 'Ligue o dia de atendimento',
    acao: 'mover e clicar',
    alvo: {
      seletor:
        '.flex.flex-col.divide-y.divide-n-weak > div:nth-child(2) button[role="switch"]',
    },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Salvar calendário',
    acao: 'mover e clicar',
    alvo: { texto: 'Salvar calendário' },
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1800,
  },
];
