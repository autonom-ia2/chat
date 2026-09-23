// Roteiro do vídeo de trajeto do artigo 02.02 — "Sua identidade: nome,
// nome de exibição e foto". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/settings.json
// (PROFILE_SETTINGS.FORM).
//
// Trajeto: Configurações do Perfil → Nome para exibição → Atualizar o
// Perfil. NÃO mexe em "Seu nome completo": é o campo que o motor usa para
// achar a usuária no login (rails runner busca por esse nome) — mudar
// quebraria as próprias gravações seguintes. "Nome para exibição" é campo
// diferente, sem esse risco, e é literalmente o exemplo do artigo ("por
// exemplo só o primeiro nome").

export const id = '02.02';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
account = Account.find(${login.contaId})
usuaria = account.users.find_by(name: ${JSON.stringify(login.usuarioNome)})
raise "usuária não encontrada" unless usuaria
usuaria.update!(display_name: nil)
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Sua identidade: nome e foto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 3200,
  },
  {
    legenda: 'Abra Configurações do Perfil',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/profile/settings`,
    aguardarTexto: 'Seu nome completo',
    zoom: 1.3,
    duracaoMs: 1200,
  },
  {
    legenda: 'Seu nome completo já vem preenchido',
    acao: 'parar',
    alvo: { seletor: 'input[placeholder="Por favor, digite seu nome completo"]' },
    zoom: 1.8,
    duracaoMs: 2200,
  },
  {
    legenda: 'Escreva o Nome para exibição',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Por favor, insira um nome de exibição para ser exibido em conversas"]',
    },
    texto: ['Rita'],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar o Perfil',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar o Perfil' },
    aguardarTextoDepois: 'atualizado com sucesso',
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 3000,
  },
];
