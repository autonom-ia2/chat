// Roteiro do vídeo de trajeto do artigo 14.03 — "Escolher o período e
// agrupar por dia, semana ou mês". Seletores conferidos no código-fonte:
// - ícone do seletor de data: `.i-lucide-calendar-range`
//   (DatePickerButton.vue) — o texto do botão muda (mostra o período
//   atual), por isso o alvo usa o ícone, fixo.
// - opções do seletor (CalendarDateRange.vue) e do Agrupar por
//   (ReportFilters.vue) são texto simples e estável (rótulos i18n
//   REPORT.DATE_RANGE_OPTIONS / REPORT.GROUPING_OPTIONS).
// "Agrupar por" só aparece depois de escolher um período com 29 dias ou
// mais (regra do próprio artigo) — por isso o vídeo escolhe "Últimos 30
// dias" antes de tentar clicar nele. Escolher o atalho só arma o
// calendário; o filtro só aplica de verdade depois de clicar em "Aplicar"
// (CalendarFooter.vue, DATE_PICKER.APPLY_BUTTON) — sem esse clique,
// `customDateRange` não muda e o botão de agrupamento não aparece. E,
// assim que aparece, ele já vem com "Dia" escolhido por padrão (primeira
// opção da lista) — o botão mostra o nome da opção atual, não mais o rótulo
// genérico "Agrupar por" (confirmado no DOM renderizado), por isso o
// próximo alvo usa o texto "Dia".

export const id = '14.03';

export const login = {
  contaId: 9,
  usuarioNome: 'Nina Admin',
};

export const baseUrl = 'http://localhost:3000';

export const cenas = [
  {
    legenda: 'Escolher o período e agrupar por',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2200,
  },
  {
    // duracaoMs maior que o padrão: os 4 gráficos da tela ficam presos em
    // "Carregando dados do gráfico…" por alguns segundos reais depois da
    // navegação — dando essa folga, o corpo do vídeo já mostra os
    // gráficos carregados a partir daqui (confirmado extraindo quadros do
    // .mp4). Isto NÃO conserta a capa/pôster — ver nota grande no fim do
    // arquivo sobre isso, já testado à exaustão nesta gravação.
    legenda: 'Abra Relatórios, Conversas',
    acao: 'ir para',
    url: `/app/accounts/${login.contaId}/reports/conversation`,
    aguardarTexto: 'Baixar relatórios de conversas',
    zoom: 1,
    duracaoMs: 3200,
  },
  {
    legenda: 'Clique no seletor de data',
    acao: 'mover e clicar',
    alvo: { seletor: '.i-lucide-calendar-range' },
    zoom: 1.8,
  },
  {
    legenda: 'Escolha Últimos 30 dias',
    acao: 'mover e clicar',
    alvo: { texto: 'Últimos 30 dias' },
    zoom: 1.6,
  },
  {
    legenda: 'Clique em Aplicar',
    acao: 'mover e clicar',
    alvo: { texto: 'Aplicar' },
    zoom: 1.6,
  },
  {
    legenda: 'Agrupar por aparece com 29+ dias',
    acao: 'parar',
    zoom: 1.3,
    duracaoMs: 1800,
  },
  {
    legenda: 'Clique em Agrupar por',
    acao: 'mover e clicar',
    alvo: { texto: 'Dia' },
    zoom: 1.6,
  },
  {
    legenda: 'Escolha Semana',
    acao: 'mover e clicar',
    alvo: { texto: 'Semana' },
    zoom: 1.6,
  },
  {
    legenda: 'O gráfico agora soma por semana',
    acao: 'parar',
    zoom: 1.2,
    duracaoMs: 1600,
  },
  {
    legenda: 'Pronto',
    acao: 'parar',
    zoom: 1,
    duracaoMs: 2400,
  },
];

// PENDÊNCIA DE MOTOR — capa (public/central-de-ajuda/videos/14.03.jpg)
// sai com "Carregando dados do gráfico…" preso nos 4 gráficos, mesmo com
// os dados prontos e a tela certa. Não é falta de espera do roteiro: eu
// testei alongando a cena de abertura pra 5,5s (não mudou nada na capa) e
// depois alongando a cena de navegação pra 4,5s (também não mudou nada).
// Extraindo quadros do .mp4 quadro a quadro, os gráficos aparecem
// carregados por volta de uns 3-4s de gravação real — ou seja, os dados
// chegam, só não a tempo da captura da capa. A capa (`gerarPoster` em
// lib/video.mjs) usa o 1º quadro do vídeo final, que corresponde ao
// instante em que a gravação começa (logo depois do `esperarSemCarregando`
// de até 10s que roda uma vez, antes da 1ª cena) — nenhum ajuste de
// duração de cena consegue empurrar esse instante pra frente, porque ele
// já passou antes da 1ª cena rodar. Preciso de motor: ou aumentar esse
// orçamento de espera pré-gravação pra telas de relatório (pode passar de
// 10s sob carga), ou capturar a capa de um quadro escolhido pelo roteiro
// (ex. do fim de uma cena marcada), em vez de sempre o quadro 0.
