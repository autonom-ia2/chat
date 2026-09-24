// Roteiro do vídeo de trajeto do artigo 12.05 — "Atributos personalizados:
// contato e conversa".
//
// Achado de produto (registrado na resposta final): os campos "Aplica-se a"
// e "Tipo" do modal usam <select> nativo do navegador — a regra do Rodrigo
// (18/09) proíbe isso. "Aplica-se a" já vem preenchido pelo tipo da aba
// escolhida (não precisa tocar); "Tipo" o vídeo troca com `selecionar`, a
// ação certa do motor pra um <select> de verdade.

export const id = '12.05';

export const login = {
  contaId: 9,
  usuarioNome: 'Rafa Admin',
};

export const baseUrl = 'http://localhost:3000';

const NOME_ATRIBUTO = 'Situação da apólice';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.custom_attribute_definitions.where(attribute_display_name: ${JSON.stringify(NOME_ATRIBUTO)}).destroy_all
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Atributos personalizados: contato e conversa',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/custom-attributes/list`,
    aguardarTexto: 'Criar atributo personalizado',
    zoom: 1,
    duracaoMs: 1000,
  },
  {
    legenda: 'Escolha a aba Contato',
    acao: 'mover e clicar',
    alvo: { texto: 'Contato' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Criar atributo personalizado',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar atributo personalizado' },
    zoom: 1.6,
  },
  {
    legenda: 'Preencha o Nome para exibição',
    acao: 'digitar',
    alvo: {
      seletor:
        'input[placeholder="Digite um nome de exibição de atributo personalizado"]',
    },
    texto: [NOME_ATRIBUTO],
    zoom: 1.8,
  },
  {
    // A Chave nasce sozinha do Nome: minúsculas, espaço vira "_", e
    // acento/cedilha somem (não viram letra sem acento).
    legenda: 'A Chave nasce sozinha do nome',
    acao: 'parar',
    alvo: { seletor: 'input[placeholder="Digite a chave de atributo personalizada"]' },
    zoom: 1.8,
    duracaoMs: 1800,
  },
  {
    legenda: 'Escreva a Descrição',
    acao: 'digitar',
    alvo: { seletor: 'textarea[placeholder="Inserir descrição do atributo personalizado"]' },
    texto: ['Status atual da apolice do cliente'],
    zoom: 1.8,
  },
  {
    legenda: 'Escolha o Tipo',
    acao: 'selecionar',
    alvo: { seletor: '#app select:has(option[value="6"])' },
    valor: '6',
    zoom: 1.8,
  },
  {
    legenda: 'Cadastre os valores da lista',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Por favor, digite o valor e pressione Enter"]' },
    texto: ['Ativa', 'Vencendo', ''],
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Criar',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar' },
    zoom: 1.6,
    aguardarTextoDepois: NOME_ATRIBUTO,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    alvo: { texto: NOME_ATRIBUTO },
    zoom: 1.4,
    duracaoMs: 1800,
  },
];
