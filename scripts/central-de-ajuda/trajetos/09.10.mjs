// Roteiro do vídeo de trajeto do artigo 09.10 — "Referência: todos os
// campos de um contato". Artigo é tabela de consulta (sem "Como faz"): o
// vídeo mostra ONDE ficam os dois grupos de campo — o formulário de
// cadastro e a seção de redes sociais — não digita nada em contato de
// outro vídeo. Rótulos conferidos no código
// (app/javascript/dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue
// e i18n pt_BR/contact.json, chave CONTACTS_LAYOUT.CARD) em 2026-09-24.
//
// Trajeto: Contatos → busca → Ver detalhes → seção "Alterar detalhes do
// contato" (nome, e-mail, telefone, país, cidade, empresa) → seção "Editar
// redes sociais".

export const id = '09.10';

export const login = {
  contaId: 9,
  usuarioNome: 'Téo Admin',
};

export const baseUrl = 'http://localhost:3007';

// Este vídeo só lê a ficha de um contato já existente na conta de teste
// (fixture usada em outros vídeos como exemplo de busca, nunca editada
// aqui) — não digita em nenhum campo dela, só navega e rola a tela, então
// não precisa preparar nada antes de gravar.
const NOME_CONTATO = 'Sandra Reis';

export const cenas = [
  {
    legenda: 'Todos os campos de um contato',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Abra Contatos',
    acao: 'mover e clicar',
    alvo: { seletor: 'nav a[name="Contacts"]' },
    zoom: 1.8,
  },
  {
    legenda: 'Busque um contato pelo nome',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Pesquisar..."]' },
    texto: [NOME_CONTATO],
    zoom: 1.8,
  },
  {
    legenda: 'Contato encontrado',
    acao: 'parar',
    alvo: { texto: 'Pesquisar contatos' },
    zoom: 1.6,
    duracaoMs: 800,
  },
  {
    legenda: 'Clique em Ver detalhes',
    acao: 'mover e clicar',
    alvo: { texto: 'Ver detalhes' },
    zoom: 1.6,
    // O clique navega para a ficha do contato — mesmo ajuste de pausas do
    // 09.03 para este mesmo botão.
    pausaAntesMs: 700,
    pausaDepoisMs: 400,
  },
  {
    legenda: 'Nome, e-mail e telefone ficam aqui',
    acao: 'parar',
    alvo: { texto: 'Alterar detalhes do contato', blocoRolagem: 'start' },
    zoom: 1.4,
    duracaoMs: 1800,
  },
  {
    legenda: 'Cidade e empresa têm campo próprio',
    acao: 'parar',
    alvo: { seletor: 'input[placeholder="Digite o nome da cidade"]' },
    zoom: 1.6,
    duracaoMs: 1400,
  },
  {
    legenda: 'Redes sociais ficam numa seção à parte',
    acao: 'parar',
    alvo: { texto: 'Editar redes sociais', blocoRolagem: 'start' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    // Só olha, não clica: o campo pertence a um contato mantido por outro
    // vídeo, e digitar aqui disparia salvamento (ContactsForm.vue emite
    // 'update' a cada tecla).
    legenda: 'Nenhuma delas entra na busca',
    acao: 'parar',
    alvo: { seletor: 'input[placeholder="Adicionar LinkedIn"]' },
    zoom: 1.8,
    duracaoMs: 1200,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 1200,
  },
];
