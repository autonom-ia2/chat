// Roteiro do vídeo de trajeto do artigo 03.01 — "Ajustar os dados gerais
// da conta". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json.
//
// Trajeto: Configurações → Conta → Nome da Conta → Idioma do site →
// Atualizar configurações. Não muda de verdade o nome nem o idioma: o
// nome da conta ("Corretora Desnorteada") aparece em todos os outros
// vídeos da série, e o idioma troca a língua de TODA a interface — mudar
// qualquer um quebraria as gravações seguintes. O roteiro digita/seleciona
// o mesmo valor que já está salvo (mesmo texto, mesma opção), o suficiente
// para mostrar a ação sem efeito colateral real.

export const id = '03.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Rita Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a preparar: o roteiro só reafirma os valores que já estão salvos.

export const cenas = [
  {
    legenda: 'Ajustar os dados gerais da conta',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 3800,
  },
  {
    legenda: 'Abra Configurações, Conta',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/general`,
    aguardarTexto: 'Nome da Conta',
    zoom: 1.3,
    duracaoMs: 1200,
  },
  {
    legenda: 'Digite o Nome da Conta',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Nome da sua conta"]' },
    limparAntes: true,
    texto: ['Corretora Desnorteada'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o Idioma do site',
    acao: 'selecionar',
    alvo: { seletor: 'select' },
    valor: 'pt_BR',
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Atualizar configurações',
    acao: 'mover e clicar',
    alvo: { texto: 'Atualizar configurações' },
    aguardarTextoDepois: 'atualizadas com sucesso',
    zoom: 1.6,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 3600,
  },
];
