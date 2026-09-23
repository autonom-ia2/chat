// Roteiro do vídeo de trajeto do artigo 10.01 — "O menu CRM e criar o
// primeiro funil". Rótulos conferidos em
// app/javascript/dashboard/i18n/locale/pt_BR/{settings,crm}.json e em
// app/javascript/dashboard/routes/dashboard/crm/components/CrmPipelineDrawer.vue.
//
// Trajeto: barra lateral → CRM → Kanban → Novo funil → nome/descrição
// (padrão) → meta mensal → Criar funil.
// O "Como faz" do artigo também cobre ligar inboxes e automação por etapa,
// mas isso fica de fora: são dois sub-fluxos extras e o vídeo já cobre os
// cliques que dão título ao artigo ("criar o primeiro funil"), dentro do
// teto de 40s. O texto do artigo cobre o resto.

export const id = '10.01';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

// "Funil Comercial" é o nome padrão que o próprio formulário de criação
// preenche sozinho (CRM_KANBAN.PIPELINE_DRAWER.DEFAULT_NAME) — não é dado
// digitado por nós. Conferido em 2026-09-23: nenhum funil real da conta 9
// usa esse nome (os reais são "Seguro Auto", "Seguro Vida", "Renovações").
// Qualquer funil com esse nome exato é sobra de uma gravação anterior deste
// vídeo; apaga só se não tiver card nenhum (nunca mexe nos funis de
// verdade).
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.crm_pipelines.where(name: "Funil Comercial").find_each do |p|
  p.destroy if p.cards.count.zero?
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Criar seu primeiro funil',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    legenda: 'Abra CRM no menu lateral',
    acao: 'mover e clicar',
    alvo: { texto: 'CRM' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Kanban',
    acao: 'mover e clicar',
    alvo: { texto: 'Kanban' },
    zoom: 1.8,
  },
  {
    legenda: 'Clique em Novo funil',
    acao: 'mover e clicar',
    alvo: { texto: 'Novo funil' },
    zoom: 1.8,
  },
  {
    legenda: 'Troque o nome e a descrição',
    acao: 'parar',
    alvo: {
      seletor: 'input[placeholder="Ex.: Vendas, Pós-venda, Renovações"]',
    },
    zoom: 2,
    duracaoMs: 1600,
  },
  {
    legenda: 'Preencha a meta mensal de vendas',
    acao: 'digitar',
    alvo: { seletor: 'input[placeholder="Ex.: 50000"]' },
    texto: ['3500'],
    zoom: 1.8,
  },
  {
    // Não usa alvo por texto: o rótulo "Criar funil" fica embaixo da bolha
    // flutuante "Guia da Plataforma" (canto inferior direito, mesma pilha
    // fixed/z-50 do rodapé do drawer — achado nesta gravação, ver relatório
    // final). Clicar no ícone do botão (mais à esquerda, fora da bolha)
    // ativa o mesmo botão sem cair embaixo dela.
    legenda: 'Clique em Criar funil',
    acao: 'mover e clicar',
    alvo: { seletor: 'span[class*="i-lucide-check"]' },
    zoom: 1.6,
  },
  {
    // Não espera o toast "Funil inicial criado.": ele já passou dos ~2,5s de
    // vida por causa da remedição pós-clique do ícone (ver comentário acima).
    // O quadro do funil novo, vazio, já mostra o resultado.
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
];
