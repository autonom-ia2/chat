import { computed } from 'vue';
import { scheduleToUtc } from 'dashboard/components-next/CampaignJourney/scheduleTime';
import { diaCurto, frase, ocorrencias } from './recorrencia';
import { nomesDeQuemRecebe, quemRecebePronto } from './quemRecebe';
import { quemRecebeParaApi, recorrenciaParaApi } from './paraApi';

// #1460/#1461/#1462 — o que o lembrete novo soma ao retorno do card: a hora no
// fuso da conta, a repetição, quem recebe e o lembrete sem card. Com a flag
// crm_lembretes_v2 desligada, nada disso aparece nem vai para a API (o
// lembrete continua como antes, no fuso do navegador).
export const useLembreteExtras = ({
  t,
  form,
  card,
  contexto,
  formato,
  locale,
  ligado,
}) => {
  const idioma = () => (locale?.value || 'pt_BR').replace('_', '-');
  // Fase 1 (decisão do Rodrigo): só o lembrete para a equipe repete.
  const podeRepetir = () =>
    ligado.value && form.automationMode === 'reminder_only';
  const repete = computed(() =>
    !podeRepetir() || form.repetir.frequencia === 'nunca' || !form.dueAt
      ? ''
      : frase({
          t,
          idioma: idioma(),
          juntar: formato.juntar,
          inicio: form.dueAt,
          repetir: form.repetir,
        })
  );
  const proximas = computed(() =>
    repete.value
      ? ocorrencias(form.dueAt, form.repetir, 4).map(dia =>
          diaCurto(dia, idioma())
        )
      : []
  );
  const quemRecebe = computed(() =>
    formato.juntar(
      nomesDeQuemRecebe({
        quem: form.quemRecebe,
        dono: contexto.dono.value?.name,
        eu: contexto.eu.value?.name,
        agentes: contexto.agentes.value,
        membros: contexto.membros.value,
      })
    )
  );
  // "Até um dia" sem o dia: falta escolher (o servidor recusaria).
  const faltaRepetir = computed(
    () =>
      Boolean(repete.value) && form.repetir.fim === 'data' && !form.repetir.ate
  );
  const pronto = computed(
    () => !ligado.value || quemRecebePronto(form.quemRecebe)
  );

  // O "quando" e o fuso que vão para a API.
  const quando = () =>
    ligado.value
      ? {
          due_at: scheduleToUtc(form.dueAt, contexto.fuso.value),
          timezone: contexto.fuso.value,
        }
      : {
          due_at: new Date(form.dueAt).toISOString(),
          timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
        };

  const payload = ligadoA => {
    if (!ligado.value) return quando();
    const recorrencia = podeRepetir()
      ? recorrenciaParaApi(form.repetir, form.dueAt)
      : null;
    return {
      ...quando(),
      ...quemRecebeParaApi(form.quemRecebe),
      ...(recorrencia ? { recurrence: recorrencia } : {}),
      ...(!card.value?.id && ligadoA?.tipo === 'contato'
        ? { contact_id: ligadoA.contatoId }
        : {}),
      ...(!card.value?.id && ligadoA?.tipo === 'empresa'
        ? { company_id: ligadoA.empresaId }
        : {}),
    };
  };

  const previa = computed(() => ({
    mostrarQuem: ligado.value,
    repete: repete.value,
    proximas: proximas.value,
    quemRecebe: ligado.value ? quemRecebe.value : '',
    quemRecebeTipo: form.quemRecebe.tipo,
  }));

  return { previa, pronto, payload, faltaRepetir };
};
