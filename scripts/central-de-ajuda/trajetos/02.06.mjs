// Roteiro do vídeo de trajeto do artigo 02.06 — "Sua disponibilidade e os
// avisos que você recebe". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (SIDEBAR.SET_YOUR_AVAILABILITY, PROFILE_SETTINGS.FORM.AVAILABILITY).
//
// Trajeto: foto → Disponibilidade (Online → Ocupado) → Configurações do
// Perfil → Preferências de notificação.

export const id = '02.06';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// O vídeo troca o status de verdade para Ocupado (não é só aparência) e
// fica assim depois de gravar — reabrir o mesmo menu uma segunda vez, só
// para voltar a Online, se mostrou instável sob carga (várias gravações
// disputando CPU ao mesmo tempo: até achar um alvo simples passou de 15s
// algumas vezes). Por isso o preparar força "online" no banco antes de
// cada gravação, em vez de tentar reverter pela UI.
export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
usuaria = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
au = AccountUser.find_by(account_id: account.id, user_id: usuaria.id)
au.update!(availability: "online")
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Sua disponibilidade e os avisos',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2600,
  },
  {
    legenda: 'Clique na sua foto',
    acao: 'mover e clicar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Disponibilidade',
    acao: 'mover e clicar',
    alvo: { texto: 'Online' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha Ocupado',
    acao: 'mover e clicar',
    alvo: { texto: 'Ocupado' },
    zoom: 1.6,
  },
  {
    legenda: 'A bolinha muda de cor',
    acao: 'parar',
    alvo: { seletor: '.border-t.border-n-weak button' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Abra Configurações do Perfil',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/profile/settings`,
    aguardarTexto: 'Preferências de notificação',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Marque e-mail ou notificação no navegador',
    acao: 'parar',
    alvo: { texto: 'Preferências de notificação', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 2000,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 2400,
  },
];
