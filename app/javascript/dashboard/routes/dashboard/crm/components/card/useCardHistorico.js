import { computed } from 'vue';
import { relativeTimeFromISO } from 'shared/helpers/timeHelper';
import {
  formatBookingTime,
  noticeKindKey,
  skipReasonKey,
} from '../../helpers/meetingNotices';

// #1423 — a linha do tempo do card, tirada da gaveta para a nova e a antiga
// usarem o mesmo texto: ícone, cor, título, quem fez, quando e o detalhe de
// cada tipo de evento. Nunca mostra erro bruto de provedor.
// Per-event-type metadata: i18n label key, lucide icon and a colour tone.
// Keyed on the actual backend Crm::Activity#event_type values.
const ACTIVITY_META = {
  create: { key: 'ACTIVITY_CREATE', icon: 'i-lucide-plus', tone: 'positive' },
  update: { key: 'ACTIVITY_UPDATE', icon: 'i-lucide-pencil', tone: 'neutral' },
  move: { key: 'ACTIVITY_MOVE', icon: 'i-lucide-arrow-right', tone: 'info' },
  won: { key: 'ACTIVITY_WON', icon: 'i-lucide-trophy', tone: 'positive' },
  lost: { key: 'ACTIVITY_LOST', icon: 'i-lucide-circle-x', tone: 'negative' },
  resolved: {
    key: 'ACTIVITY_RESOLVED',
    icon: 'i-lucide-circle-check',
    tone: 'positive',
  },
  cancelled: {
    key: 'ACTIVITY_CANCELLED',
    icon: 'i-lucide-circle-x',
    tone: 'negative',
  },
  reopen: {
    key: 'ACTIVITY_REOPEN',
    icon: 'i-lucide-rotate-ccw',
    tone: 'neutral',
  },
  archive: { key: 'ACTIVITY_ARCHIVE', icon: 'i-lucide-archive', tone: 'muted' },
  conversation_linked: {
    key: 'ACTIVITY_LINK_CONVERSATION',
    icon: 'i-lucide-link',
    tone: 'info',
  },
  conversation_unlinked: {
    key: 'ACTIVITY_UNLINK_CONVERSATION',
    icon: 'i-lucide-unlink',
    tone: 'muted',
  },
  contact_linked: {
    key: 'ACTIVITY_LINK_CONTACT',
    icon: 'i-lucide-user-plus',
    tone: 'info',
  },
  contact_unlinked: {
    key: 'ACTIVITY_UNLINK_CONTACT',
    icon: 'i-lucide-user-minus',
    tone: 'muted',
  },
  conversation_sync: {
    key: 'ACTIVITY_CONVERSATION_SYNC',
    icon: 'i-lucide-refresh-cw',
    tone: 'neutral',
  },
  conversation_dedup_reuse: {
    key: 'ACTIVITY_CONVERSATION_DEDUP_REUSE',
    icon: 'i-lucide-layers',
    tone: 'neutral',
  },
  follow_up_created: {
    key: 'ACTIVITY_FOLLOW_UP_CREATED',
    icon: 'i-lucide-bell-plus',
    tone: 'info',
  },
  follow_up_updated: {
    key: 'ACTIVITY_FOLLOW_UP_UPDATED',
    icon: 'i-lucide-bell',
    tone: 'neutral',
  },
  follow_up_completed: {
    key: 'ACTIVITY_FOLLOW_UP_COMPLETED',
    icon: 'i-lucide-check',
    tone: 'positive',
  },
  follow_up_canceled: {
    key: 'ACTIVITY_FOLLOW_UP_CANCELED',
    icon: 'i-lucide-bell-off',
    tone: 'muted',
  },
  follow_up_overdue: {
    key: 'ACTIVITY_FOLLOW_UP_OVERDUE',
    icon: 'i-lucide-alarm-clock',
    tone: 'negative',
  },
  follow_up_message_sent: {
    key: 'ACTIVITY_FOLLOW_UP_MESSAGE_SENT',
    icon: 'i-lucide-send',
    tone: 'positive',
  },
  follow_up_message_failed: {
    key: 'ACTIVITY_FOLLOW_UP_DELIVERY_FAILED',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
  follow_up_rescheduled: {
    key: 'ACTIVITY_FOLLOW_UP_RESCHEDULED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  meeting_scheduled: {
    key: 'ACTIVITY_MEETING_SCHEDULED',
    icon: 'i-lucide-video',
    tone: 'info',
  },
  meeting_rescheduled: {
    key: 'ACTIVITY_MEETING_RESCHEDULED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  meeting_canceled: {
    key: 'ACTIVITY_MEETING_CANCELED',
    icon: 'i-lucide-calendar-x',
    tone: 'negative',
  },
  meeting_outcome_recorded: {
    key: 'ACTIVITY_MEETING_OUTCOME',
    icon: 'i-lucide-circle-check',
    tone: 'info',
  },
  // Agendamento (#1188): quem atendia saiu da conta e a reunião foi para outra pessoa. `nameLabel` põe o nome de
  // quem recebeu no título (labels.to_user_id, resolvido no backend).
  meeting_host_reassigned: {
    key: 'ACTIVITY_MEETING_HOST_REASSIGNED',
    nameLabel: 'to_user_id',
    icon: 'i-lucide-user-check',
    tone: 'info',
  },
  // Agendamento (#1192): o que o cliente fez pelo link e aviso no WhatsApp que não saiu.
  booking_client_confirmed: {
    key: 'ACTIVITY_BOOKING_CLIENT_CONFIRMED',
    icon: 'i-lucide-circle-check',
    tone: 'positive',
  },
  booking_client_canceled: {
    key: 'ACTIVITY_BOOKING_CLIENT_CANCELED',
    icon: 'i-lucide-calendar-x',
    tone: 'negative',
  },
  booking_client_rescheduled: {
    key: 'ACTIVITY_BOOKING_CLIENT_RESCHEDULED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  booking_client_rebooked: {
    key: 'ACTIVITY_BOOKING_CLIENT_REBOOKED',
    icon: 'i-lucide-calendar-plus',
    tone: 'positive',
  },
  booking_notice_failed: {
    key: 'ACTIVITY_BOOKING_NOTICE_FAILED',
    icon: 'i-lucide-message-circle-warning',
    tone: 'negative',
  },
  booking_notices_stopped: {
    key: 'ACTIVITY_BOOKING_NOTICES_STOPPED',
    icon: 'i-lucide-bell-off',
    tone: 'muted',
  },
  // Dia da reunião (#1193): o agente lembrou o cliente e mandou o link para remarcar.
  booking_agent_reminded: {
    key: 'ACTIVITY_BOOKING_AGENT_REMINDED',
    icon: 'i-lucide-bell-ring',
    tone: 'info',
  },
  booking_rebook_link_sent: {
    key: 'ACTIVITY_BOOKING_REBOOK_LINK_SENT',
    icon: 'i-lucide-calendar-plus',
    tone: 'info',
  },
  automation_owner_assigned: {
    key: 'ACTIVITY_AUTOMATION_OWNER_ASSIGNED',
    icon: 'i-lucide-user-check',
    tone: 'info',
  },
  automation_stage_moved: {
    key: 'ACTIVITY_AUTOMATION_STAGE_MOVED',
    icon: 'i-lucide-arrow-right',
    tone: 'info',
  },
  automation_follow_up_created: {
    key: 'ACTIVITY_AUTOMATION_FOLLOW_UP_CREATED',
    icon: 'i-lucide-bell-plus',
    tone: 'info',
  },
  ai_auto_moved: {
    key: 'ACTIVITY_AI_AUTO_MOVED',
    icon: 'i-lucide-sparkles',
    tone: 'info',
  },
  ai_suggested: {
    key: 'ACTIVITY_AI_SUGGESTED',
    icon: 'i-lucide-lightbulb',
    tone: 'info',
  },
  ai_dismissed: {
    key: 'ACTIVITY_AI_DISMISSED',
    icon: 'i-lucide-x',
    tone: 'muted',
  },
  ai_handoff: {
    key: 'ACTIVITY_AI_HANDOFF',
    icon: 'i-lucide-user-check',
    tone: 'info',
  },
  // #1975: a IA pediu uma pessoa (na hora da decisão) e a fila tirou um pedido já resolvido.
  ai_handoff_requested: {
    key: 'ACTIVITY_AI_HANDOFF_REQUESTED',
    icon: 'i-lucide-hand',
    tone: 'info',
  },
  ai_handoff_withdrawn: {
    key: 'ACTIVITY_AI_HANDOFF_WITHDRAWN',
    icon: 'i-lucide-undo-2',
    tone: 'muted',
  },
  // Fase D: handoff do agente nativo Autonom.ia. Reusa o mesmo visual do handoff
  // do Kanban; o detalhe nunca expõe motivo bruto do LLM (payload só ids/strategy).
  autonomia_handoff: {
    key: 'ACTIVITY_AUTONOMIA_HANDOFF',
    icon: 'i-lucide-user-check',
    tone: 'info',
  },
  ai_followup_planned: {
    key: 'ACTIVITY_AI_FOLLOWUP_PLANNED',
    icon: 'i-lucide-calendar-clock',
    tone: 'info',
  },
  ai_followup_reset: {
    key: 'ACTIVITY_AI_FOLLOWUP_RESET',
    icon: 'i-lucide-rotate-ccw',
    tone: 'neutral',
  },
  ai_followup_stopped: {
    key: 'ACTIVITY_AI_FOLLOWUP_STOPPED',
    icon: 'i-lucide-circle-stop',
    tone: 'muted',
  },
  ai_followup_failed: {
    key: 'ACTIVITY_AI_FOLLOWUP_FAILED',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
  ai_followup_sent: {
    key: 'ACTIVITY_AI_FOLLOWUP_SENT',
    icon: 'i-lucide-send',
    tone: 'positive',
  },
  ai_followup_capped: {
    key: 'ACTIVITY_AI_FOLLOWUP_CAPPED',
    icon: 'i-lucide-circle-stop',
    tone: 'muted',
  },
  ai_followup_completed: {
    key: 'ACTIVITY_AI_FOLLOWUP_COMPLETED',
    icon: 'i-lucide-check-circle-2',
    tone: 'positive',
  },
  ai_handoff_invite: {
    key: 'ACTIVITY_AI_HANDOFF_INVITE',
    icon: 'i-lucide-user-round-plus',
    tone: 'info',
  },
  ai_handoff_pickup: {
    key: 'ACTIVITY_AI_HANDOFF_PICKUP',
    icon: 'i-lucide-user-check',
    tone: 'positive',
  },
  ai_handoff_escalation: {
    key: 'ACTIVITY_AI_HANDOFF_ESCALATION',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
  ai_handoff_renotify: {
    key: 'ACTIVITY_AI_HANDOFF_RENOTIFY',
    icon: 'i-lucide-bell-ring',
    tone: 'neutral',
  },
  // Motor de entrega (#1454): convite que nunca saiu, passado o prazo.
  entrega_sem_ninguem: {
    key: 'ACTIVITY_ENTREGA_SEM_NINGUEM',
    icon: 'i-lucide-triangle-alert',
    tone: 'negative',
  },
};

const FALLBACK_META = { icon: 'i-lucide-history', tone: 'neutral' };

const ACTIVITY_TONE_CLASSES = {
  positive: 'bg-n-teal-3 text-n-teal-11',
  negative: 'bg-n-ruby-3 text-n-ruby-11',
  info: 'bg-n-blue-3 text-n-blue-11',
  neutral: 'bg-n-alpha-2 text-n-slate-11',
  muted: 'bg-n-slate-4 text-n-slate-10',
};

// Agendamento (#1192): o que o cliente fez pelo link leva by: 'client' no
// payload ("Aviso não saiu" leva by: 'system'). Só eventos do agendamento.

// `textos` (opcional): prefixo de i18n com títulos próprios por tipo de evento;
// o que não tiver lá usa o texto de sempre (CRM_KANBAN.DRAWER). Pode ser uma
// função que devolve a lista de prefixos, em ordem (#1498: Atender primeiro).
export const useCardHistorico = ({
  t,
  te,
  locale,
  activities,
  textos = '',
}) => {
  const prefixos = () =>
    (typeof textos === 'function' ? textos() : [textos]).filter(Boolean);
  const proprio = chave =>
    (te &&
      prefixos()
        .map(prefixo => `${prefixo}.${chave}`)
        .find(opcao => te(opcao))) ||
    '';
  // Texto do detalhe: o próprio da gaveta nova, se houver; senão, o de sempre.
  const detalhe = (chave, valores) =>
    t(proprio(chave) || `CRM_KANBAN.DRAWER.${chave}`, valores);
  const isClientBookingEvent = activity =>
    String(activity.event_type || '').startsWith('booking_') &&
    activity.payload?.by === 'client';

  // AI work runs as a system actor (actor_type === 'system'). ai_dismissed is a
  // human action (actor_type === 'user'), so it is NOT keyed on the 'ai_' prefix.
  const activityActor = activity => {
    if (isClientBookingEvent(activity)) {
      return t('CRM_KANBAN.DRAWER.CLIENT_ACTOR');
    }
    if (activity.actor_type === 'system') {
      return activity.event_type?.startsWith('ai_')
        ? t(proprio('AI_ACTOR') || 'CRM_KANBAN.DRAWER.AI_ACTOR')
        : t('CRM_KANBAN.DRAWER.SYSTEM_ACTOR');
    }
    return activity.actor_name || t('CRM_KANBAN.DRAWER.UNKNOWN_ACTOR');
  };

  // Returns the readable label for an id-bearing payload key, preferring the
  // backend-provided labels{} map and falling back to a "#id" reference.
  const activityLabelValue = (activity, key) => {
    const labels = activity.labels || {};
    if (labels[key]) return labels[key];
    const raw = activity.payload?.[key];
    return raw ? `#${raw}` : '';
  };

  // Provider/LLM errors are diagnostic data, not user-facing copy. Never read
  // payload.error or metadata.send_error in the drawer because they can contain
  // arbitrary provider text.

  // Attempt copy is shown only when the activity carries an explicit counter.
  // `touch` is a cadence position, not a retry count, so it must not be used here.
  const activityAttemptDetail = activity => {
    const attempts = Number(activity.payload?.attempts);
    if (!Number.isInteger(attempts) || attempts < 1) return '';
    return detalhe('ACTIVITY_DETAIL_ATTEMPT', {
      attempt: attempts,
    });
  };

  const activityRetryAtDetail = activity => {
    const retryAt = activity.payload?.retry_at;
    if (!retryAt || Number.isNaN(new Date(retryAt).getTime())) return '';
    return detalhe('ACTIVITY_DETAIL_RETRY_AT', {
      time: relativeTimeFromISO(retryAt, locale.value),
    });
  };

  const activityRetryDetail = activity => {
    const details = [
      activityAttemptDetail(activity),
      activityRetryAtDetail(activity),
    ];
    if (activity.payload?.final === true) {
      details.push(detalhe('ACTIVITY_DETAIL_ATTEMPTS_FINISHED'));
    }
    return details.filter(Boolean).join(' · ');
  };

  // Builds a friendly one-line description for the activity. Returns '' when the
  // event type has no extra detail worth rendering.
  const activityDetail = activity => {
    switch (activity.event_type) {
      case 'move':
      case 'ai_auto_moved':
      case 'ai_suggested': {
        const from = activityLabelValue(activity, 'from_stage_id');
        const to = activityLabelValue(activity, 'to_stage_id');
        if (from && to)
          return detalhe('ACTIVITY_DETAIL_STAGE_CHANGE', {
            from,
            to,
          });
        if (to) return detalhe('ACTIVITY_DETAIL_STAGE_TO', { to });
        return '';
      }
      case 'automation_stage_moved': {
        const to = activityLabelValue(activity, 'target_stage_id');
        return to ? detalhe('ACTIVITY_DETAIL_STAGE_TO', { to }) : '';
      }
      case 'automation_owner_assigned': {
        const owner = activityLabelValue(activity, 'owner_id');
        return owner ? detalhe('ACTIVITY_DETAIL_OWNER', { owner }) : '';
      }
      case 'ai_handoff': {
        const agent = activityLabelValue(activity, 'assignee_id');
        const reason = activity.payload?.reason;
        if (agent && reason)
          return detalhe('ACTIVITY_DETAIL_HANDOFF_REASON', {
            agent,
            reason,
          });
        if (agent) return detalhe('ACTIVITY_DETAIL_HANDOFF', { agent });
        return reason || '';
      }
      // #1975: o motivo que a IA deu (qual problema ficou aberto, ou o que resolveu).
      case 'ai_handoff_requested':
      case 'ai_handoff_withdrawn':
        return activity.payload?.reason || '';
      // Fase D: handoff do agente nativo. Mostra só o destino (membro do inbox ou
      // time); nunca há `reason` no payload (IP oculto).
      case 'autonomia_handoff': {
        const assignee = activityLabelValue(activity, 'assignee_id');
        if (assignee)
          return detalhe('ACTIVITY_DETAIL_HANDOFF', {
            agent: assignee,
          });
        const team = activityLabelValue(activity, 'team_id');
        return team
          ? detalhe('ACTIVITY_DETAIL_AUTONOMIA_HANDOFF_TEAM', {
              team,
            })
          : '';
      }
      case 'contact_linked':
      case 'contact_unlinked': {
        const contact = activityLabelValue(activity, 'contact_id');
        return contact ? detalhe('ACTIVITY_DETAIL_CONTACT', { contact }) : '';
      }
      // chat#737: follow-up automático cancelado porque o contato recusou mensagens ativas.
      case 'follow_up_canceled': {
        const title = activity.payload?.title || '';
        if (activity.payload?.reason !== 'opt_out') return title;
        const reason = detalhe('ACTIVITY_DETAIL_FOLLOW_UP_OPT_OUT');
        return title ? `${title} · ${reason}` : reason;
      }
      case 'follow_up_created':
      case 'follow_up_updated':
      case 'follow_up_completed':
      case 'follow_up_overdue':
      case 'follow_up_message_sent': {
        const title = activity.payload?.title;
        return title || activityAttemptDetail(activity);
      }
      case 'follow_up_message_failed':
        return [activity.payload?.title, activityRetryDetail(activity)]
          .filter(Boolean)
          .join(' · ');
      case 'ai_followup_failed':
        return activityRetryDetail(activity);
      case 'ai_followup_sent':
      case 'ai_followup_capped':
      case 'ai_followup_completed':
        return activityAttemptDetail(activity);
      case 'follow_up_rescheduled': {
        const dueAt = activity.payload?.due_at;
        if (!dueAt || Number.isNaN(new Date(dueAt).getTime())) return '';
        return detalhe('ACTIVITY_DETAIL_FOLLOW_UP_RESCHEDULED', {
          time: relativeTimeFromISO(dueAt, locale.value),
        });
      }
      case 'booking_client_rescheduled': {
        const from = formatBookingTime(activity.payload?.from, locale.value);
        const to = formatBookingTime(activity.payload?.starts_at, locale.value);
        if (from && to)
          return detalhe('ACTIVITY_DETAIL_BOOKING_MOVED', {
            from,
            to,
          });
        return to ? detalhe('ACTIVITY_DETAIL_BOOKING_TIME', { time: to }) : '';
      }
      case 'booking_notice_failed': {
        const kind = noticeKindKey(activity.payload?.kind);
        const reason = activity.payload?.reason;
        const base = 'CRM_KANBAN.CALENDAR.MEETING_DETAIL.NOTICES';
        if (!kind) return '';
        // Motivo de pulo conhecido tem texto; erro do envio (classe, interrupted,
        // delivery_failed) aparece como "Falhou".
        const reasonKey = skipReasonKey(reason);
        const reasonText = t(
          reasonKey === 'OTHER'
            ? `${base}.STATUS.FAILED`
            : `${base}.SKIP_REASONS.${reasonKey}`
        );
        return detalhe('ACTIVITY_DETAIL_BOOKING_NOTICE_FAILED', {
          kind: t(`${base}.KINDS.${kind}`),
          reason: reasonText,
        });
      }
      case 'booking_client_confirmed':
      case 'booking_client_canceled':
      case 'booking_client_rebooked':
      case 'booking_notices_stopped':
      case 'booking_agent_reminded':
      case 'booking_rebook_link_sent': {
        const time = formatBookingTime(
          activity.payload?.starts_at,
          locale.value
        );
        return time ? detalhe('ACTIVITY_DETAIL_BOOKING_TIME', { time }) : '';
      }
      case 'meeting_scheduled':
      case 'meeting_rescheduled':
      case 'meeting_canceled': {
        const title = activity.payload?.title;
        // #1196 (J6-A4): reunião marcada pela IA na conversa.
        if (
          activity.event_type === 'meeting_scheduled' &&
          activity.payload?.source === 'ai'
        ) {
          return t(
            proprio('BOOKED_BY_AI_DETAIL') ||
              'BOOKING.AI_AGENT.BOOKED_BY_AI_DETAIL',
            {
              title: title || '',
            }
          );
        }
        return title ? detalhe('ACTIVITY_DETAIL_MEETING', { title }) : '';
      }
      default:
        return '';
    }
  };

  // Título com o nome de quem recebeu, quando o evento tem `nameLabel` e o nome veio; senão, o título fixo.
  const activityTitle = (activity, meta) => {
    if (!meta.key)
      return t(
        proprio('ACTIVITY_GENERIC') || 'CRM_KANBAN.DRAWER.ACTIVITY_GENERIC'
      );
    const name = meta.nameLabel ? activity.labels?.[meta.nameLabel] : null;
    if (name) return t(`CRM_KANBAN.DRAWER.${meta.key}_TO`, { name });
    return t(proprio(meta.key) || `CRM_KANBAN.DRAWER.${meta.key}`);
  };

  // Single source of truth for rendering a timeline entry. Hard non-JSON
  // fallback: unknown event types still produce a humanized label + icon.
  const describeActivity = activity => {
    const meta = ACTIVITY_META[activity.event_type] || FALLBACK_META;
    const title = activityTitle(activity, meta);
    return {
      title,
      icon: meta.icon,
      toneClass:
        ACTIVITY_TONE_CLASSES[meta.tone] || ACTIVITY_TONE_CLASSES.neutral,
      actor: activityActor(activity),
      detail: activityDetail(activity),
      relativeTime: relativeTimeFromISO(activity.created_at, locale.value),
    };
  };

  // Um auto-move da IA grava DUAS atividades para um único movimento físico:
  // 'ai_auto_moved' (auditoria da decisão do modelo) e 'move' (evento canônico do
  // Crm::Cards::Mover). As duas TÊM que continuar existindo no banco — só 'move'
  // está na allowlist de webhooks do Crm::Webhooks::Emitter e alimenta o sync de
  // conversão Meta CAPI. Aqui a timeline colapsa o par em uma linha só, mantendo
  // a da IA (mais informativa). Nada muda no backend.
  const AI_MOVE_DEDUP_WINDOW_MS = 60 * 1000;

  const stageTransitionKey = activity => {
    const from = activity.payload?.from_stage_id;
    const to = activity.payload?.to_stage_id;
    return from && to ? `${from}->${to}` : null;
  };

  const activityTime = activity => new Date(activity.created_at).getTime();

  // Só o 'move' escrito PELA IA é candidato: o Mover recebe actor nil no caminho
  // do SuggestionApplier (-> actor_type 'system'), enquanto movimento humano leva
  // Current.user (-> actor_type 'user'). Sem esse filtro, um humano refazendo a
  // mesma transição logo depois do auto-move sumiria da timeline.
  const isCollapsibleMove = activity =>
    activity.event_type === 'move' &&
    activity.actor_type === 'system' &&
    stageTransitionKey(activity) !== null;

  // Janela DIRECIONAL: o 'move' da IA é sempre gravado DEPOIS do ai_auto_moved
  // (o SuggestionRecorder roda antes do SuggestionApplier), então movimento
  // anterior nunca é par. created_at chega serializado com .iso8601 — precisão de
  // segundo —, logo empates de distância são esperados e o desempate é por id.
  const matchesAiMove = (move, aiMove) => {
    if (stageTransitionKey(move) !== stageTransitionKey(aiMove)) return false;
    // O 'move' é sempre a linha inserida DEPOIS, então o id também tem que ser
    // maior. Isso desempata dois ciclos de IA da mesma transição no mesmo segundo,
    // que o timestamp truncado sozinho não distingue.
    if (Number(move.id) <= Number(aiMove.id)) return false;
    const delta = activityTime(move) - activityTime(aiMove);
    return delta >= 0 && delta <= AI_MOVE_DEDUP_WINDOW_MS;
  };

  // Pareamento 1:1: cada ai_auto_moved consome no máximo um 'move' — o mais
  // próximo no tempo e, no empate, o de menor id. Dois auto-moves da mesma
  // transição na janela nunca escondem três linhas.
  const collapsedMoveIds = computed(() => {
    const aiMoves = activities.value.filter(
      activity => activity.event_type === 'ai_auto_moved'
    );
    if (aiMoves.length === 0) return new Set();

    const candidates = activities.value.filter(isCollapsibleMove);
    return aiMoves.reduce((collapsed, aiMove) => {
      const [nearest] = candidates
        .filter(move => !collapsed.has(move.id) && matchesAiMove(move, aiMove))
        .sort(
          (a, b) =>
            activityTime(a) - activityTime(b) || Number(a.id) - Number(b.id)
        );
      return nearest ? new Set([...collapsed, nearest.id]) : collapsed;
    }, new Set());
  });

  const visibleActivities = computed(() =>
    collapsedMoveIds.value.size === 0
      ? activities.value
      : activities.value.filter(
          activity => !collapsedMoveIds.value.has(activity.id)
        )
  );

  const timelineEntries = computed(() =>
    visibleActivities.value.map(activity => ({
      id: activity.id,
      ...describeActivity(activity),
    }))
  );

  // A linha do tempo agrupada por dia (Hoje, Ontem, data), da mais nova para a
  // mais velha, como chega do servidor.
  const diaDe = iso => {
    const data = new Date(iso);
    if (Number.isNaN(data.getTime())) return '';
    return data.toDateString();
  };
  const rotuloDoDia = (iso, agora = new Date()) => {
    const data = new Date(iso);
    const ontem = new Date(agora);
    ontem.setDate(agora.getDate() - 1);
    if (data.toDateString() === agora.toDateString())
      return t('CRM_CARD.HISTORICO.HOJE');
    if (data.toDateString() === ontem.toDateString())
      return t('CRM_CARD.HISTORICO.ONTEM');
    return new Intl.DateTimeFormat(locale.value.replace('_', '-'), {
      day: 'numeric',
      month: 'long',
    }).format(data);
  };
  const porDia = computed(() =>
    visibleActivities.value.reduce((dias, activity) => {
      const dia = diaDe(activity.created_at);
      const entrada = {
        id: activity.id,
        tipo: activity.event_type,
        ...describeActivity(activity),
      };
      const ultimo = dias.at(-1);
      if (ultimo && ultimo.dia === dia)
        return [
          ...dias.slice(0, -1),
          { ...ultimo, itens: [...ultimo.itens, entrada] },
        ];
      return [
        ...dias,
        { dia, rotulo: rotuloDoDia(activity.created_at), itens: [entrada] },
      ];
    }, [])
  );

  return { describeActivity, timelineEntries, porDia };
};
