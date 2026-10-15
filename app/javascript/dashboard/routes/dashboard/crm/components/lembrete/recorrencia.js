// #1460 — a repetição de um lembrete, em conta de calendário (dia e hora de
// parede, no fuso da conta). "2026-10-20T10:00" + "toda segunda" → as próximas
// datas. As contas usam Date.UTC só como calculadora: nenhum fuso entra aqui,
// e a hora de parede nunca anda (10:00 continua 10:00 no horário de verão).
export const FREQUENCIAS = ['nunca', 'dia', 'semana', 'mes', 'ano'];
export const FINS = ['nunca', 'data', 'vezes'];

export const repetirVazio = () => ({
  frequencia: 'nunca',
  soDiasUteis: false,
  dias: [],
  fim: 'nunca',
  ate: '',
  vezes: 10,
});

const DIA_MS = 86400000;
const MAXIMO_DE_VOLTAS = 1200;

const ler = texto => {
  const [dia, hora = '09:00'] = String(texto || '').split('T');
  const [ano, mes, numero] = dia.split('-').map(Number);
  const [h, m] = hora.split(':').map(Number);
  if (!ano || !mes || !numero) return null;
  return { ano, mes, numero, h: h || 0, m: m || 0 };
};
const data = (ano, mes, numero, h, m) =>
  new Date(Date.UTC(ano, mes - 1, numero, h, m));
const ultimoDia = (ano, mes) => new Date(Date.UTC(ano, mes, 0)).getUTCDate();
const fimDeSemana = dia => [0, 6].includes(dia.getUTCDay());

// O dia da semana do começo entra sozinho em "toda semana" quando a pessoa
// ainda não escolheu nenhum.
export const diasDaSemana = (repetir, inicio) => {
  // Segunda primeiro, domingo por último, como a semana de quem trabalha.
  if (repetir.dias.length)
    return [...repetir.dias].sort((a, b) => ((a + 6) % 7) - ((b + 6) % 7));
  const p = ler(inicio);
  return p ? [data(p.ano, p.mes, p.numero, 0, 0).getUTCDay()] : [];
};

const candidata = (p, repetir, volta) => {
  switch (repetir.frequencia) {
    case 'dia':
    case 'semana':
      return new Date(
        data(p.ano, p.mes, p.numero, p.h, p.m).getTime() + volta * DIA_MS
      );
    case 'mes': {
      const total = p.mes - 1 + volta;
      const ano = p.ano + Math.floor(total / 12);
      const mes = (total % 12) + 1;
      return data(ano, mes, Math.min(p.numero, ultimoDia(ano, mes)), p.h, p.m);
    }
    case 'ano':
      return data(
        p.ano + volta,
        p.mes,
        Math.min(p.numero, ultimoDia(p.ano + volta, p.mes)),
        p.h,
        p.m
      );
    default:
      return volta ? null : data(p.ano, p.mes, p.numero, p.h, p.m);
  }
};

const entra = (dia, repetir, semana) => {
  if (repetir.frequencia === 'dia' && repetir.soDiasUteis)
    return !fimDeSemana(dia);
  if (repetir.frequencia === 'semana') return semana.includes(dia.getUTCDay());
  return true;
};

// As datas da série, a partir do começo. `quantas` corta a lista mostrada;
// o fim escolhido ("até 15/12", "10 vezes") corta a série.
export const ocorrencias = (inicio, repetir, quantas = 5) => {
  const p = ler(inicio);
  if (!p) return [];
  const semana = diasDaSemana(repetir, inicio);
  const ate = repetir.fim === 'data' ? ler(`${repetir.ate}T23:59`) : null;
  const limite = ate ? data(ate.ano, ate.mes, ate.numero, 23, 59) : null;
  const teto = repetir.fim === 'vezes' ? Number(repetir.vezes) || 1 : Infinity;
  const lista = [];
  for (let volta = 0; volta < MAXIMO_DE_VOLTAS; volta += 1) {
    if (lista.length >= Math.min(quantas, teto)) break;
    const dia = candidata(p, repetir, volta);
    if (!dia || (limite && dia > limite)) break;
    if (entra(dia, repetir, semana)) lista.push(dia);
  }
  return lista;
};

// Quantas vezes a série tem ao todo (Infinity quando não tem fim).
export const totalDeVezes = (inicio, repetir) => {
  if (repetir.frequencia === 'nunca') return 1;
  if (repetir.fim === 'nunca') return Infinity;
  return ocorrencias(inicio, repetir, MAXIMO_DE_VOLTAS).length;
};

// Volta ao texto de parede ("2026-10-20T10:00"), para o calendário.
export const paraTexto = dia => dia.toISOString().slice(0, 16);

const formatador = (idioma, opcoes) =>
  new Intl.DateTimeFormat(idioma, { ...opcoes, timeZone: 'UTC' });

// O ano só aparece quando não é o deste ano ("qui., 14/01/27").
const outroAno = dia => dia.getUTCFullYear() !== new Date().getFullYear();

export const diaCurto = (dia, idioma) =>
  formatador(idioma, {
    weekday: 'short',
    day: '2-digit',
    month: '2-digit',
    year: outroAno(dia) ? '2-digit' : undefined,
  }).format(dia);

export const diaLongo = (dia, idioma) =>
  formatador(idioma, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    year: outroAno(dia) ? 'numeric' : undefined,
  }).format(dia);

export const nomeDoDia = (numero, idioma, estilo = 'long') =>
  formatador(idioma, { weekday: estilo }).format(
    new Date(Date.UTC(1970, 0, 4 + numero))
  );

export const horaDe = inicio => String(inicio || '').slice(11, 16) || '09:00';

// "Toda segunda e quarta, às 10:00", "Todo dia 10, às 09:00"…
export const frase = ({ t, idioma, juntar, inicio, repetir }) => {
  const p = ler(inicio);
  if (!p) return '';
  const hora = horaDe(inicio);
  const C = 'CRM_LEMBRETE.REPETIR.FRASE';
  switch (repetir.frequencia) {
    case 'dia':
      return t(repetir.soDiasUteis ? `${C}.DIA_UTIL` : `${C}.DIA`, { hora });
    case 'semana': {
      // "segunda-feira" vira "segunda". Segunda primeiro: se o primeiro é
      // sábado ou domingo, todos são, e a frase pede "Todo".
      const dias = diasDaSemana(repetir, inicio);
      const fimDeSemanaSo = [0, 6].includes(dias[0]);
      return t(fimDeSemanaSo ? `${C}.SEMANA_FIM` : `${C}.SEMANA`, {
        dias: juntar(
          dias.map(numero => nomeDoDia(numero, idioma).split('-')[0])
        ),
        hora,
      });
    }
    case 'mes':
      return t(p.numero > 28 ? `${C}.MES_FIM` : `${C}.MES`, {
        dia: p.numero,
        hora,
      });
    case 'ano':
      return t(`${C}.ANO`, {
        dia: formatador(idioma, { day: 'numeric', month: 'long' }).format(
          data(p.ano, p.mes, p.numero, 0, 0)
        ),
        hora,
      });
    default:
      return t(`${C}.UMA_VEZ`);
  }
};

// Um instante (ISO) visto como dia e hora de parede num fuso:
// "2026-10-19T13:00:00Z" em America/Sao_Paulo → "2026-10-19T10:00".
export const paredeDe = (iso, fuso) => {
  const partes = Object.fromEntries(
    new Intl.DateTimeFormat('en-US', {
      timeZone: fuso,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    })
      .formatToParts(new Date(iso))
      .map(parte => [parte.type, parte.value])
  );
  return `${partes.year}-${partes.month}-${partes.day}T${partes.hour}:${partes.minute}`;
};

// O texto de parede como data de calculadora (as funções acima leem em UTC).
export const diaDaParede = texto => new Date(`${texto}:00Z`);
