// Roteiro do vídeo de trajeto do artigo 03.04 — "Trazer contatos de outra
// ferramenta e acompanhar a importação".
//
// Serviço de fora (Intercom): o campo da chave de acesso valida no @blur
// (NewImportDialog.vue) — bate na API do Intercom de verdade assim que o
// campo perde o foco. O vídeo tem que TERMINAR logo depois de digitar a
// chave, com uma cena "parar" (nunca clica em mais nada depois, `parar`
// não dispara clique) — qualquer clique daqui pra frente tiraria o foco do
// campo e disparia a validação de verdade.
//
// Achado de produto (registrado na resposta final): o campo "Fonte" usa
// `dashboard/components-next/select/Select.vue`, que por baixo é um
// `<select>` nativo do navegador (só estilizado) — a regra do Rodrigo
// (18/09) proíbe isso. Fica no padrão "Intercom", sem precisar tocar.

export const id = '03.04';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Trazer contatos de outra ferramenta',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/data`,
    aguardarTexto: 'Importar',
    zoom: 1,
    duracaoMs: 1800,
  },
  {
    // Duas coisas na tela dizem "Importar" (a aba e o botão) — mira pelo
    // ícone do botão de verdade (o que abre o formulário).
    legenda: 'Clique em Importar',
    acao: 'mover e clicar',
    alvo: { texto: 'Importar' },
    zoom: 1.6,
    aguardarTextoDepois: 'Nova importação',
  },
  {
    legenda: 'Escolha a Fonte',
    acao: 'parar',
    alvo: { seletor: 'select' },
    zoom: 1.6,
    duracaoMs: 2400,
  },
  {
    legenda: 'Dê um nome à importação',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Migração do suporte de julho"]' },
    texto: ['Migracao clientes antigos - Intercom'],
    limparAntes: true,
    zoom: 1.8,
  },
  {
    // Última cena com clique/foco no formulário — a próxima já é "parar".
    legenda: 'Cole a chave de acesso',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Cole sua chave de acesso do Intercom"]' },
    texto: ['chave-fake-video-nao-usar'],
    zoom: 1.8,
  },
  {
    // Fecho: formulário preenchido, sem clicar em mais nada — tirar o foco
    // do campo da chave dispara a validação de verdade na API do
    // Intercom. Marca Contatos e Conversas, já selecionados por padrão.
    legenda: 'Marque o que importar e clique em Importar',
    acao: 'parar',
    alvo: { texto: 'Dados para importar' },
    zoom: 1.4,
    duracaoMs: 3200,
  },
];
