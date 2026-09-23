// Roteiro do vídeo de trajeto do artigo 12.03 — "Criar e organizar
// Etiquetas". Seletores conferidos no código-fonte
// (app/javascript/dashboard/routes/dashboard/settings/labels/AddLabel.vue):
// `data-testid="label-title"` / `"label-description"` ficam no atributo
// herdado da raiz do componente `woot-input`
// (app/javascript/dashboard/components/widgets/forms/Input.vue), que é o
// `<label>`, não o `<input>` — por isso o alvo usa o seletor descendente
// `label[data-testid=...] input`.
//
// O vídeo cria de verdade a etiqueta "financeiro" (nome realista de
// corretora, não "etiqueta-teste") — por isso o preparar apaga essa
// etiqueta antes de cada gravação, para o clique em Criar nunca esbarrar
// num nome já existente (a API rejeita título duplicado).
//
// Trajeto: Configurações → Etiquetas → Adicionar etiqueta → preenche nome e
// descrição → Criar.

export const id = '12.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
etiqueta = conta.labels.find_by(title: "financeiro")
etiqueta&.destroy!
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar e organizar Etiquetas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Configurações, Etiquetas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/settings/labels/list`,
    aguardarTexto: 'Adicionar etiqueta',
    zoom: 1,
    duracaoMs: 1200,
  },
  {
    legenda: 'Clique em Adicionar etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'Adicionar etiqueta' },
    zoom: 1.6,
  },
  {
    legenda: 'Escreva o nome da etiqueta',
    acao: 'digitar',
    alvo: { seletor: 'label[data-testid="label-title"] input' },
    texto: ['financeiro'],
    zoom: 1.8,
  },
  {
    legenda: 'Escreva a descrição',
    acao: 'digitar',
    alvo: { seletor: 'label[data-testid="label-description"] input' },
    texto: ['Pendências financeiras da apólice'],
    zoom: 1.6,
  },
  {
    legenda: 'Escolha a Cor',
    acao: 'parar',
    alvo: { seletor: '.colorpicker--selected' },
    zoom: 1.5,
    duracaoMs: 1400,
  },
  {
    legenda: 'Marque Exibir na barra lateral',
    acao: 'parar',
    alvo: { texto: 'Exibir etiqueta na barra lateral' },
    zoom: 1.4,
    duracaoMs: 1400,
  },
  {
    legenda: 'Clique em Criar',
    acao: 'mover e clicar',
    alvo: { texto: 'Criar' },
    zoom: 1.6,
  },
  {
    legenda: 'Etiqueta adicionada com sucesso',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
