import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { rotuloDoFuso } from 'dashboard/helper/fusoDaConta';
import { idiomaDoNavegador } from '../utils/pagina';
import { duracaoDoGanho, periodoDoGanho } from '../utils/desempenhoContrato';

// #2226 — o t do i18n e os formatos do idioma da pessoa, num objeto só, para o painel de desempenho
// (aba Resumo e aba Detalhe). As datas dos dados chegam como 'AAAA-MM-DD' ou 'AAAA-MM-DDTHH:mm', já no
// fuso da conta: são lidas no dia local, sem passar por UTC. Valor que não dá para calcular (null)
// vira "—", nunca zero.
const NS = 'AGENTS.DESEMPENHO2.A.FORMATO';
const SEM_VALOR = '—';
const SEGUNDOS_POR_MINUTO = 60;
const SEGUNDOS_POR_HORA = 3600;
const DIAS = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];

const partesDe = dataHora => {
  const [dia, hora = '00:00'] = String(dataHora).split('T');
  const [ano, mes, diaDoMes] = dia.split('-').map(Number);
  const [horas, minutos] = hora.split(':').map(Number);
  return { ano, mes, diaDoMes, horas, minutos };
};

const dataLocal = dataHora => {
  const { ano, mes, diaDoMes, horas, minutos } = partesDe(dataHora);
  return new Date(ano, mes - 1, diaDoMes, horas || 0, minutos || 0);
};

const vazio = valor => valor === null || valor === undefined;

export function useFormatoDoPainel() {
  const { t, te, locale } = useI18n();
  const idioma = computed(() => idiomaDoNavegador(locale.value));

  const n = valor => Number(valor || 0).toLocaleString(idioma.value);
  const decimal = valor =>
    Number(valor).toLocaleString(idioma.value, {
      minimumFractionDigits: 0,
      maximumFractionDigits: 1,
    });
  const pct = valor =>
    vazio(valor)
      ? SEM_VALOR
      : Number(valor / 100).toLocaleString(idioma.value, {
          style: 'percent',
          minimumFractionDigits: 1,
          maximumFractionDigits: 1,
        });
  const dinheiro = (valor, moeda = 'BRL') =>
    vazio(valor)
      ? SEM_VALOR
      : Number(valor).toLocaleString(idioma.value, {
          style: 'currency',
          currency: moeda || 'BRL',
          maximumFractionDigits: 0,
        });
  const data = iso =>
    dataLocal(iso).toLocaleDateString(idioma.value, {
      day: '2-digit',
      month: '2-digit',
    });
  const hora = dataHora => {
    const { horas, minutos } = partesDe(dataHora);
    return `${String(horas || 0).padStart(2, '0')}:${String(minutos || 0).padStart(2, '0')}`;
  };
  const dataHora = valor => `${data(valor)} ${hora(valor)}`;
  // 'AAAA-MM' -> "jun. de 2026" (mês curto e ano, no idioma da pessoa).
  const mes = anoMes => {
    const [ano, numero] = String(anoMes).split('-').map(Number);
    return new Date(ano, (numero || 1) - 1, 1).toLocaleDateString(
      idioma.value,
      { month: 'short', year: 'numeric' }
    );
  };
  // Chave montada com um id que vem dos dados: id que o i18n não conhece mostra a reserva, nunca a
  // chave crua.
  const tSeTiver = (chave, reserva, valores = {}) =>
    te(chave) ? t(chave, valores) : reserva;
  // Pontos sempre com 1 casa ("5,0 pontos", "4,7 pontos"), igual ao PDF e à planilha.
  const umaCasa = valor =>
    Number(valor).toLocaleString(idioma.value, {
      minimumFractionDigits: 1,
      maximumFractionDigits: 1,
    });
  const pontos = valor =>
    vazio(valor)
      ? SEM_VALOR
      : t(
          `${NS}.PONTOS`,
          { n: umaCasa(Math.abs(valor)) },
          Math.abs(valor) === 1 ? 1 : 2
        );
  // 33 -> "33 s"; 70 -> "1 min 10 s" (nunca arredonda 70 s para "1 min"); 3600 ou mais -> "1,5 h".
  const segundos = valor => {
    if (vazio(valor)) return SEM_VALOR;
    const total = Math.round(valor);
    if (total < SEGUNDOS_POR_MINUTO)
      return t(`${NS}.SEGUNDOS`, { n: n(total) });
    if (total < SEGUNDOS_POR_HORA) {
      const minutos = Math.floor(total / SEGUNDOS_POR_MINUTO);
      const resto = total % SEGUNDOS_POR_MINUTO;
      return resto
        ? t(`${NS}.MINUTOS_E_SEGUNDOS`, { m: n(minutos), s: n(resto) })
        : t(`${NS}.MINUTOS`, { n: n(minutos) });
    }
    return t(`${NS}.HORAS`, { n: decimal(total / SEGUNDOS_POR_HORA) });
  };
  // ['a', 'b', 'c'] -> "a, b e c", com o "e" do idioma da pessoa.
  const lista = itens => {
    const validos = (itens || []).filter(Boolean);
    try {
      return new Intl.ListFormat(idioma.value, { type: 'conjunction' }).format(
        validos
      );
    } catch {
      return validos.join(', ');
    }
  };
  // 0 = segunda … 6 = domingo (a ordem das linhas do mapa de calor).
  const diaDaSemana = indice => t(`${NS}.DIA_CURTO.${DIAS[indice]}`);
  const diaDaSemanaLongo = indice => t(`${NS}.DIA_LONGO.${DIAS[indice]}`);
  const periodo = intervalo =>
    intervalo
      ? t(`${NS}.PERIODO`, {
          inicio: data(intervalo.inicio),
          fim: data(intervalo.fim),
        })
      : '';
  // "30 dias" / "4 meses": a duração do período de um ganho.
  const duracao = dias => {
    const { unidade, n: quantos } = duracaoDoGanho(Number(dias) || 0);
    return t(`${NS}.DURACAO_${unidade}`, { n: n(quantos) }, quantos);
  };
  // O ganho sempre diz de que datas é: "≈ 4 vendas a mais · ≈ R$ 1.360 em 30 dias (27/09 a 26/10)".
  // Quando a conta usou o histórico completo: "neste período ainda não dá para estimar; no histórico
  // completo (4 meses, 25/06 a 26/10): ≈ 19 vendas a mais". Sem conta: ''.
  const fraseDoGanho = (ganho, painel, { comValor = true } = {}) => {
    const partes = [];
    if (!vazio(ganho?.fechamentos)) {
      partes.push(
        t(
          'AGENTS.DESEMPENHO2.A.ACOES.GANHO_FECHAMENTOS',
          { n: n(ganho.fechamentos) },
          ganho.fechamentos
        )
      );
    }
    if (comValor && !vazio(ganho?.valor)) {
      partes.push(
        t('AGENTS.DESEMPENHO2.A.ACOES.GANHO_VALOR', {
          valor: dinheiro(ganho.valor, painel?.ticket?.moeda),
        })
      );
    }
    const intervalo = periodoDoGanho(ganho, painel);
    if (!partes.length || !intervalo) return '';
    const chave = ganho.historico ? 'GANHO_DO_HISTORICO' : 'GANHO_NO_PERIODO';
    return t(`AGENTS.DESEMPENHO2.A.ACOES.${chave}`, {
      ganho: partes.join(' · '),
      duracao: duracao(intervalo.dias),
      inicio: data(intervalo.inicio),
      fim: data(intervalo.fim),
    });
  };
  // O fuso da conta como a plataforma mostra em Configurações ("America/Sao Paulo"), igual ao PDF.
  // Regra do Rodrigo: nunca o nome longo do navegador ("Horário Padrão de …").
  const fuso = iana => rotuloDoFuso(iana);
  // O número do KPI no formato que o contrato pede.
  const valorDoKpi = kpi => {
    if (!kpi) return SEM_VALOR;
    if (kpi.formato === 'pct') return pct(kpi.valor);
    if (kpi.formato === 'segundos') return segundos(kpi.valor);
    if (kpi.formato === 'dinheiro') return dinheiro(kpi.valor);
    return vazio(kpi.valor) ? SEM_VALOR : n(kpi.valor);
  };

  return {
    t,
    idioma,
    fraseDoGanho,
    n,
    decimal,
    pct,
    pontos,
    segundos,
    lista,
    dinheiro,
    data,
    hora,
    dataHora,
    mes,
    tSeTiver,
    diaDaSemana,
    diaDaSemanaLongo,
    periodo,
    fuso,
    valorDoKpi,
  };
}
