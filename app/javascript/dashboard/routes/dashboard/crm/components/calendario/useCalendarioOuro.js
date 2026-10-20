// Calendário Ouro — o estado da tela: que visão, que dia, o que mostrar, e a
// janela de datas que o back precisa buscar (sempre no fuso da conta).
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import {
  chaveDoDia,
  inicioDaSemana,
  inicioDoMes,
  instanteNaConta,
  minutosDoDia,
  semanasDoMes,
  somarDias,
  somarMeses,
} from './tempoNaConta';
import { ORDEM_DOS_TIPOS, paraItem } from './itensDoCalendario';

// Busca um ano para trás: o que atrasou há mais de 30 dias não some calado,
// aparece como "E mais N antigos" no fim do "Ficou para trás".
const DIAS_PARA_TRAS = 365;
const DIAS_A_FRENTE = 8;
const UM_MINUTO = 60 * 1000;

// #1883: `inicial` é o filtro que veio pelo link (quem e tipos); a tela abre com ele ligado.
const tiposLigados = lista =>
  lista?.length
    ? Object.fromEntries(
        ORDEM_DOS_TIPOS.map(tipo => [tipo, lista.includes(tipo)])
      )
    : {};

export const useCalendarioOuro = ({ props, fuso, ehAdmin, inicial = null }) => {
  const agora = ref(new Date());
  let relogio = null;
  onMounted(() => {
    relogio = setInterval(() => {
      agora.value = new Date();
    }, UM_MINUTO);
  });
  onBeforeUnmount(() => clearInterval(relogio));

  const hoje = computed(() => chaveDoDia(agora.value, fuso.value));
  const agoraMinutos = computed(() => minutosDoDia(agora.value, fuso.value));

  const visao = ref('dia');
  const dia = ref(hoje.value);
  // Virou o dia com a tela aberta: quem estava em "hoje" passa para o novo hoje.
  watch(hoje, (novo, antigo) => {
    if (dia.value === antigo) dia.value = novo;
  });
  const mesDoMini = ref(inicioDoMes(hoje.value));
  watch(dia, novo => {
    mesDoMini.value = inicioDoMes(novo);
  });

  // Decisão 4 do #1568: administrador vê toda a equipe; agente, só os seus.
  // Segue o papel até a pessoa escolher no "Mostrar" (o papel pode chegar depois).
  const quemEscolhido = ref(inicial?.quem || null);
  const quemPadrao = computed(() => (ehAdmin.value ? 'todos' : 'meus'));
  const quem = computed({
    get: () => quemEscolhido.value || quemPadrao.value,
    set: valor => {
      quemEscolhido.value = valor;
    },
  });
  const tipos = ref(tiposLigados(inicial?.tipos));
  const feitos = ref(false);

  const tiposDisponiveis = computed(() =>
    ORDEM_DOS_TIPOS.filter(tipo => {
      if (tipo === 'mensagem') return props.temWhatsapp;
      if (tipo === 'reuniao') return props.reunioesLigadas;
      if (tipo === 'agenda')
        return props.events.some(e => e.event_type === 'external');
      return true;
    })
  );
  const filtrosLigados = computed(
    () =>
      tiposDisponiveis.value.filter(tipo => tipos.value[tipo] === false)
        .length +
      (quem.value !== quemPadrao.value ? 1 : 0) +
      (feitos.value ? 1 : 0)
  );

  // Janela de busca: no "Meu dia", 30 dias para trás (o que atrasou) até a
  // semana que vem, cobrindo também o mês pequeno ao lado.
  const janela = computed(() => {
    if (visao.value === 'semana') {
      const de = inicioDaSemana(dia.value);
      return { de, ate: somarDias(de, 6) };
    }
    if (visao.value === 'mes') {
      const semanas = semanasDoMes(dia.value);
      return { de: semanas[0][0], ate: semanas.at(-1)[6] };
    }
    const mini = semanasDoMes(mesDoMini.value);
    const candidatosDe = [
      somarDias(hoje.value, -DIAS_PARA_TRAS),
      mini[0][0],
      dia.value,
    ];
    const candidatosAte = [
      somarDias(hoje.value, DIAS_A_FRENTE),
      mini.at(-1)[6],
      somarDias(dia.value, 1),
    ];
    return { de: candidatosDe.sort()[0], ate: candidatosAte.sort().at(-1) };
  });

  // "Só os meus": o que está no meu nome. As vezes calculadas de um lembrete
  // que repete trazem o responsável que terão (#1568). Sem dono, ou sem saber
  // quem é a pessoa, não é "meu".
  const vazio = valor => valor === null || valor === undefined;
  const ehMeu = item => {
    const { assignee_id: dono } = item.evento;
    if (vazio(dono) || vazio(props.currentUserId)) return false;
    return Number(dono) === Number(props.currentUserId);
  };

  const itens = computed(() =>
    (props.events || [])
      .map(evento => paraItem(evento, { fuso: fuso.value, agora: agora.value }))
      .filter(item => tipos.value[item.tipo] !== false)
      .filter(item => tiposDisponiveis.value.includes(item.tipo))
      .filter(item => feitos.value || !item.feito)
      .filter(item => quem.value !== 'meus' || ehMeu(item))
  );

  const marcas = computed(() => {
    const mapa = {};
    itens.value.forEach(item => {
      if (item.feito) return;
      if (item.atrasado && item.chave < hoje.value)
        mapa[item.chave] = 'atrasado';
      else mapa[item.chave] ||= 'tem';
    });
    return mapa;
  });

  const andar = passo => {
    if (visao.value === 'semana') dia.value = somarDias(dia.value, 7 * passo);
    else if (visao.value === 'mes') dia.value = somarMeses(dia.value, passo);
    else dia.value = somarDias(dia.value, passo);
  };
  const irParaHoje = () => {
    dia.value = hoje.value;
  };
  const noPeriodoDeHoje = computed(() => {
    if (visao.value === 'semana')
      return inicioDaSemana(dia.value) === inicioDaSemana(hoje.value);
    if (visao.value === 'mes')
      return dia.value.slice(0, 7) === hoje.value.slice(0, 7);
    return dia.value === hoje.value;
  });

  const instante = (chave, hora) => instanteNaConta(chave, hora, fuso.value);

  return {
    agora,
    hoje,
    agoraMinutos,
    visao,
    dia,
    mesDoMini,
    quem,
    tipos,
    feitos,
    tiposDisponiveis,
    filtrosLigados,
    janela,
    itens,
    marcas,
    ehMeu,
    andar,
    irParaHoje,
    noPeriodoDeHoje,
    instante,
  };
};
