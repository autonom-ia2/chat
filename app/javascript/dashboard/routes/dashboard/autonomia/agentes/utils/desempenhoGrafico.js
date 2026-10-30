// #2226 v2 — as contas dos gráficos SVG do painel de desempenho, sem nada de tela: escala do eixo Y
// com números redondos, posição de cada ponto, o traço da linha e da área, quais datas aparecem no
// eixo X e o degrau de tamanho da bolha nas faixas de eventos. O SVG usa viewBox 0 0 1000 300 e
// cada ponto fica no meio da sua coluna (as colunas em HTML usam flex-1 e caem no mesmo lugar).
export const LARGURA = 1000;
export const ALTURA = 300;
export const LINHAS_DA_GRADE = 4;
export const DATAS_NO_EIXO = 7;

const PASSOS_REDONDOS = [1, 2, 2.5, 5, 10];

// O passo redondo (1, 2, 2,5 ou 5 × 10^k) que cobre o máximo em `linhas` faixas.
const passoRedondo = (maximo, linhas) => {
  const bruto = maximo / linhas;
  const potencia = 10 ** Math.floor(Math.log10(bruto));
  const passo = PASSOS_REDONDOS.find(fator => fator * potencia >= bruto);
  return Math.max(1, passo * potencia);
};

// { topo, marcas: [topo … 0] }: as marcas vão de cima para baixo, como o eixo é lido.
export const escalaRedonda = (maximo, linhas = LINHAS_DA_GRADE) => {
  const alto = Math.max(0, Number(maximo) || 0);
  if (!alto)
    return {
      topo: linhas,
      marcas: Array.from({ length: linhas + 1 }, (_, i) => linhas - i),
    };
  const passo = passoRedondo(alto, linhas);
  const topo = passo * linhas;
  return {
    topo,
    marcas: Array.from({ length: linhas + 1 }, (_, i) => topo - passo * i),
  };
};

export const xDoIndice = (indice, total) =>
  total ? ((indice + 0.5) / total) * LARGURA : 0;

export const yDoValor = (valor, topo) =>
  topo ? ALTURA - (Math.max(0, valor || 0) / topo) * ALTURA : ALTURA;

const ponto = (valor, indice, total, topo) =>
  `${xDoIndice(indice, total).toFixed(1)} ${yDoValor(valor, topo).toFixed(1)}`;

// O traço da linha entre os índices [de, ate] (inclusive). Vazio quando não há 2 pontos.
export const tracoDaLinha = (
  valores,
  topo,
  de = 0,
  ate = valores.length - 1
) => {
  if (ate - de < 1) return '';
  return valores
    .slice(de, ate + 1)
    .map(
      (valor, i) =>
        `${i ? 'L' : 'M'} ${ponto(valor, de + i, valores.length, topo)}`
    )
    .join(' ');
};

// A área embaixo da linha principal, fechada no chão do gráfico.
export const tracoDaArea = (valores, topo) => {
  if (valores.length < 2) return '';
  const total = valores.length;
  const chao = ALTURA.toFixed(1);
  return `${tracoDaLinha(valores, topo)} L ${xDoIndice(total - 1, total).toFixed(1)} ${chao} L ${xDoIndice(0, total).toFixed(1)} ${chao} Z`;
};

// Um ponto desenhado como traço de comprimento zero com ponta redonda: com
// vector-effect="non-scaling-stroke" ele fica redondo mesmo com o SVG esticado.
export const tracoDoPonto = (valor, indice, total, topo) =>
  `M ${ponto(valor, indice, total, topo)} l 0 0`;

// Quais índices ganham data no eixo X: no máximo `maximo`, sempre o primeiro e o último.
export const indicesDoEixo = (total, maximo = DATAS_NO_EIXO) => {
  if (total <= 0) return [];
  if (total <= maximo) return Array.from({ length: total }, (_, i) => i);
  const passo = (total - 1) / (maximo - 1);
  return Array.from({ length: maximo }, (_, i) => Math.round(i * passo));
};

// O índice do maior valor (o primeiro, em empate); -1 sem valores.
export const indiceDoPico = valores =>
  valores.reduce(
    (pico, valor, indice) =>
      valor > (valores[pico] ?? -Infinity) ? indice : pico,
    valores.length ? 0 : -1
  );

// Bolha da faixa de eventos: raio proporcional à raiz do número, em 5 degraus (1 a 5); zero = 0.
export const DEGRAUS_DA_BOLHA = 5;
export const degrauDaBolha = (valor, maximo) => {
  if (!valor || !maximo) return 0;
  const fracao = Math.sqrt(valor) / Math.sqrt(maximo);
  return Math.max(1, Math.ceil(fracao * DEGRAUS_DA_BOLHA));
};

// O pico do mapa de calor (dia 0 = segunda, hora 0–23). Sem nenhuma procura, valor 0 e dia -1.
export const picoDoMapa = mapa =>
  mapa.reduce(
    (pico, linha, dia) =>
      linha.reduce(
        (atual, valor, hora) =>
          valor > atual.valor ? { dia, hora, valor } : atual,
        pico
      ),
    { dia: -1, hora: -1, valor: 0 }
  );

const DIAS_DA_SEMANA = 7;
const PONTOS_NA_PONTA = 4;

// O ritmo de uma série por semana, no começo e no fim do período: a média dos primeiros e dos
// últimos pontos inteiros (sem o dia ou a semana em andamento ou cortada). Por semana, até 4 de cada
// lado; por dia, a primeira e a última semana inteiras (7 dias, × 7), só com 14 dias ou mais, para o
// fim de semana não distorcer. Sem pontos suficientes: null.
export const ritmoDaSerie = (pontos, campo, unidade) => {
  const inteiros = (pontos || []).filter(item => !item.parcial);
  const porDia = unidade === 'dia';
  if (porDia && inteiros.length < 2 * DIAS_DA_SEMANA) return null;
  if (!porDia && inteiros.length < 2) return null;
  const ponta = porDia
    ? DIAS_DA_SEMANA
    : Math.max(1, Math.min(PONTOS_NA_PONTA, Math.floor(inteiros.length / 3)));
  const fator = porDia ? DIAS_DA_SEMANA : 1;
  const media = lista =>
    (lista.reduce((acc, item) => acc + (item[campo] || 0), 0) / lista.length) *
    fator;
  // `semanas`: quantas semanas inteiras entram em cada média (para a frase dizer de onde vem a conta).
  return {
    antes: media(inteiros.slice(0, ponta)),
    depois: media(inteiros.slice(-ponta)),
    semanas: porDia ? 1 : ponta,
  };
};

// O topo do eixo com 4 ou 5 linhas: o que deixar menos espaço vazio acima do maior valor.
export const escalaJusta = maximo => {
  const opcoes = [4, 5].map(linhas => escalaRedonda(maximo, linhas));
  return opcoes.reduce((melhor, opcao) =>
    opcao.topo < melhor.topo ? opcao : melhor
  );
};
