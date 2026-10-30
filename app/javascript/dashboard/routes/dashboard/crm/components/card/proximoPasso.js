// #1423 — o "Próximo passo" do card: uma coisa só em destaque e até duas
// "Depois disso". A ordem é fixa e vem de dados que o detalhe do card já traz:
//   1. reunião de hoje (ainda por começar ou acontecendo);
//   2. retorno atrasado;
//   3. o cliente mandou mensagem e espera resposta (waiting_since da conversa
//      principal, que o servidor só manda quando a pessoa pode ver a conversa);
//      ou chegou pelo formulário do anúncio da Meta e ninguém falou com ele
//      ainda (#2195);
//   4. sugestão de etapa;
//   5. retorno de hoje;
//   6. tudo em dia.
// Negócio que já terminou fica com "fechado" no destaque, antes de tudo.
// Funções puras: recebem "agora" para os testes não dependerem do relógio.

const ABERTOS = ['pending', 'overdue'];
const MAX_DEPOIS = 2;

const data = valor => {
  if (valor === null || valor === undefined || valor === '') return null;
  const numero = Number(valor);
  // waiting_since chega em segundos; o resto em ISO.
  const resultado =
    Number.isFinite(numero) && typeof valor !== 'string'
      ? new Date(numero * 1000)
      : new Date(valor);
  return Number.isNaN(resultado.getTime()) ? null : resultado;
};

const mesmoDia = (a, b) => a.toDateString() === b.toDateString();

const porData = (a, b) => data(a.due_at) - data(b.due_at);

const retornosAbertos = retornos =>
  (retornos || [])
    .filter(item => ABERTOS.includes(item.status) && data(item.due_at))
    .sort(porData);

export const atrasado = (retorno, agora) =>
  retorno.status === 'overdue' || data(retorno.due_at) < agora;

export const passosDoCard = ({
  reuniao = null,
  retornos = [],
  esperaDesde = null,
  sugestao = null,
  formulario = null,
  status = 'open',
  agora = new Date(),
} = {}) => {
  const passos = [];
  // Negócio que já terminou (ganho, perdido…): nada a cobrar no destaque.
  if (status && status !== 'open') passos.push({ tipo: 'fechado' });
  const inicio = data(reuniao?.starts_at);
  if (inicio && mesmoDia(inicio, agora))
    passos.push({ tipo: 'reuniao_hoje', reuniao, quando: inicio });

  const abertos = retornosAbertos(retornos);
  const atrasados = abertos.filter(item => atrasado(item, agora));
  if (atrasados.length)
    passos.push({
      tipo: 'retorno_atrasado',
      retorno: atrasados[0],
      quando: data(atrasados[0].due_at),
      total: atrasados.length,
    });

  const espera = data(esperaDesde);
  if (espera) passos.push({ tipo: 'espera', quando: espera });
  if (formulario) passos.push({ tipo: 'formulario', formulario });

  if (sugestao?.id && sugestao.to_stage_name)
    passos.push({ tipo: 'sugestao', sugestao });

  const deHoje = abertos.find(
    item => !atrasado(item, agora) && mesmoDia(data(item.due_at), agora)
  );
  if (deHoje)
    passos.push({
      tipo: 'retorno_hoje',
      retorno: deHoje,
      quando: data(deHoje.due_at),
    });

  // Informativos, só para "Depois disso": a próxima reunião e o próximo
  // retorno que não são de hoje.
  const futuros = [];
  if (inicio && !mesmoDia(inicio, agora) && inicio > agora)
    futuros.push({ tipo: 'reuniao_futura', reuniao, quando: inicio });
  const proximo = abertos.find(
    item => !atrasado(item, agora) && !mesmoDia(data(item.due_at), agora)
  );
  if (proximo)
    futuros.push({
      tipo: 'retorno_futuro',
      retorno: proximo,
      quando: data(proximo.due_at),
    });

  const [principal = { tipo: 'em_dia' }, ...resto] = passos;
  return {
    principal,
    depois: [...resto, ...futuros].slice(0, MAX_DEPOIS),
  };
};
