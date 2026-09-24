// Roteiro do vídeo de trajeto do artigo 14.07 — "Visão Geral das
// Etiquetas". Mesmo padrão do 14.06 (Agentes): tabela → clique no nome de
// uma etiqueta → detalhe com gráfico e seta de tendência → seta de voltar.
// A etiqueta "sinistro" já tem uso real na conta (macro do vídeo 08.10 a
// aplicou numa conversa) — não precisa nada no preparar.
//
// Seletores conferidos no código-fonte:
// - cabeçalho da tela: "Baixar relatórios de etiquetas"
//   (LABEL_REPORTS.DOWNLOAD_LABEL_REPORTS).
// - seta de voltar: `.i-lucide-chevron-left` (mesmo componente BackButton
//   do 14.06).
//
// Trajeto: Relatórios → Etiquetas → clique em "sinistro" → detalhe → volta
// → mostra o botão de baixar CSV (sem clicar).

export const id = '14.07';

export const login = {
  contaId: 9,
  usuarioNome: 'Lia Admin',
};

export const baseUrl = 'http://localhost:3000';

// Nada a criar: a etiqueta "sinistro" já tem conversa de verdade (o 08.10
// aplicou via macro). Só confere que ela existe, sem depender da ordem de
// gravação dos outros vídeos.
export async function preparar({ rodarRails }) {
  await rodarRails(`
conta = Account.find(${login.contaId})
conta.labels.find_or_create_by!(title: "sinistro") do |l|
  l.color = "#F44343"
end
puts "preparo-ok"
`);
}

export const cenas = [
  {
    legenda: 'Visão Geral das Etiquetas',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
  {
    legenda: 'Abra Relatórios, Etiquetas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/labels_overview`,
    aguardarTexto: 'Baixar relatórios de etiquetas',
    zoom: 1,
    duracaoMs: 1400,
  },
  {
    legenda: 'Leia a tabela por etiqueta',
    acao: 'parar',
    alvo: { texto: 'Nº de Conversas' },
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique no nome de uma etiqueta',
    acao: 'mover e clicar',
    alvo: { texto: 'sinistro' },
    zoom: 1.6,
  },
  {
    legenda: 'Veja o detalhe e a tendência',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique na seta de voltar',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-chevron-left' },
    zoom: 1.8,
  },
  {
    legenda: 'Baixe o CSV, se quiser',
    acao: 'parar',
    alvo: { texto: 'Baixar relatórios de etiquetas' },
    zoom: 1.6,
    duracaoMs: 1600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];
