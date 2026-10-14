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

const DIAS_PARA_TRAS = 30;
const DIAS_A_FRENTE = 8;
const UM_MINUTO = 60 * 1000;

export const useCalendarioOuro = ({ props, fuso, quemPadrao }) => {
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
  const mesDoMini = ref(inicioDoMes(hoje.value));
  watch(dia, novo => {
    mesDoMini.value = inicioDoMes(novo);
  });

  const quem = ref(quemPadrao);
  const tipos = ref({});
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
      (quem.value === 'meus' ? 1 : 0) +
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

  const itens = computed(() =>
    (props.events || [])
      .map(evento => paraItem(evento, { fuso: fuso.value, agora: agora.value }))
      .filter(item => tipos.value[item.tipo] !== false)
      .filter(item => tiposDisponiveis.value.includes(item.tipo))
      .filter(item => feitos.value || !item.feito)
      .filter(
        item =>
          quem.value !== 'meus' ||
          Number(item.evento.assignee_id) === Number(props.currentUserId)
      )
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
    andar,
    irParaHoje,
    noPeriodoDeHoje,
    instante,
  };
};
