import { ref } from 'vue';
import { withFullI18n } from '../../../../../../../../../vitest.i18n';
import { useCardHistorico } from '../useCardHistorico';

// O texto de cada evento do histórico do card (#1423), com a cópia real (não
// as chaves) para provar o que a pessoa lê. Veio da gaveta antiga
// (o spec da linha do tempo dela), agora sobre o composable que a gaveta nova usa,
// com os títulos próprios dela (CRM_CARD.HISTORICO.EVENTO).
const i18n = withFullI18n('en');
const { t, te } = i18n.global;

const PROVIDER_ERROR = 'Meta API 131047 raw';
const now = new Date().toISOString();
const inOneHour = new Date(Date.now() + 60 * 60 * 1000).toISOString();

const activity = (id, eventType, payload, extra = {}) => ({
  id,
  event_type: eventType,
  actor_type: 'system',
  payload,
  created_at: now,
  ...extra,
});

const historico = (activities = []) =>
  useCardHistorico({
    t,
    te,
    locale: ref('en'),
    activities: ref(activities),
    textos: 'CRM_CARD.HISTORICO.EVENTO',
  });
const describeActivity = item => historico().describeActivity(item);
const textoDe = activities =>
  historico(activities)
    .porDia.value.flatMap(dia => dia.itens)
    .map(item => [item.title, item.detail, item.actor].join(' '))
    .join(' ');

describe('useCardHistorico — texto de cada evento', () => {
  it('never shows the raw provider error of a failed follow-up', () => {
    const activities = [
      activity(1, 'follow_up_message_failed', {
        follow_up_id: 7,
        title: 'Enviar proposta',
        error: PROVIDER_ERROR,
      }),
      activity(
        2,
        'ai_followup_failed',
        { touch: 1, error: PROVIDER_ERROR, attempts: 1, retry_at: inOneHour },
        { metadata: { send_error: PROVIDER_ERROR } }
      ),
    ];
    const texto = textoDe(activities);

    activities.forEach(item => {
      expect(describeActivity(item).detail).not.toContain(PROVIDER_ERROR);
    });
    expect(texto).toContain(
      t('CRM_CARD.HISTORICO.EVENTO.ACTIVITY_AI_FOLLOWUP_FAILED')
    );
    expect(texto).not.toContain(PROVIDER_ERROR);
    expect(texto).not.toContain('131047');
  });

  // #2694: o dono escolhido por uma pessoa vence o "atribuir dono" da automação.
  it('says the chosen owner stayed when the stage automation kept it', () => {
    const kept = activity(
      1,
      'automation_owner_kept',
      { owner_id: 8 },
      { labels: { owner_id: 'Paula Ribeiro' } }
    );
    const { title, detail } = describeActivity(kept);

    expect(title).toBe(
      'An automatic rule would change who takes care, but the person chosen stays'
    );
    expect(detail).toContain('Paula Ribeiro');
  });

  it('shows the follow-up title on a failed manual follow-up', () => {
    const failed = activity(1, 'follow_up_message_failed', {
      follow_up_id: 7,
      title: 'Enviar proposta',
      error: PROVIDER_ERROR,
    });
    const texto = textoDe([failed]);

    expect(describeActivity(failed).detail).toBe('Enviar proposta');
    expect(texto).toContain('Enviar proposta');
  });

  it('shows attempt and next retry time on a failed AI follow-up', () => {
    const { detail } = describeActivity(
      activity(1, 'ai_followup_failed', {
        touch: 3,
        attempts: 2,
        retry_at: inOneHour,
      })
    );

    expect(detail).toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPT', { attempt: 2 })
    );
    expect(detail).toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_RETRY_AT', { time: '' }).trim()
    );
    expect(detail).not.toContain(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPTS_FINISHED')
    );
  });

  it('says attempts are finished on the final AI follow-up failure', () => {
    const { detail } = describeActivity(
      activity(1, 'ai_followup_failed', { attempts: 3, final: true })
    );

    expect(detail).toBe(
      [
        t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPT', { attempt: 3 }),
        t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_ATTEMPTS_FINISHED'),
      ].join(' · ')
    );
  });

  it.each([[{}], [{ attempts: 0 }], [{ touch: 2 }]])(
    'shows no retry detail on a failed AI follow-up without a counter (%o)',
    payload => {
      expect(
        describeActivity(activity(1, 'ai_followup_failed', payload)).detail
      ).toBe('');
    }
  );

  it('says who received a reassigned meeting, in plain words', () => {
    const reassigned = activity(
      1,
      'meeting_host_reassigned',
      { meeting_id: 9, from_user_id: 3, to_user_id: 4 },
      { labels: { to_user_id: 'Camila Torres' } }
    );

    const described = describeActivity(reassigned);

    expect(described.title).toBe('Meeting moved to Camila Torres');
    expect(described.icon).toBe('i-lucide-user-check');
    expect(described.title).not.toContain('#4');
  });

  it('falls back to a nameless title when the new host name is missing', () => {
    const { title } = describeActivity(
      activity(1, 'meeting_host_reassigned', { to_user_id: 4 })
    );

    expect(title).toBe('Meeting moved to someone else');
  });

  it('has the pt_BR copy for the reassigned meeting', () => {
    const ptBR = { locale: 'pt_BR' };

    expect(
      t(
        'CRM_KANBAN.DRAWER.ACTIVITY_MEETING_HOST_REASSIGNED_TO',
        { name: 'Camila' },
        ptBR
      )
    ).toBe('Reunião passou para Camila');
    expect(
      t('CRM_KANBAN.DRAWER.ACTIVITY_MEETING_HOST_REASSIGNED', {}, ptBR)
    ).toBe('Reunião passou para outra pessoa');
  });

  it.each([
    ['booking_client_confirmed', 'Customer confirmed the time'],
    ['booking_client_canceled', 'Customer cancelled the time'],
    ['booking_client_rebooked', 'Customer booked another time'],
    ['booking_notices_stopped', 'Customer asked not to get notices'],
  ])('describes %s in plain words, with the booked time', (type, title) => {
    const described = describeActivity(
      activity(1, type, {
        meeting_id: 9,
        starts_at: '2026-10-20T13:00:00Z',
        by: 'client',
      })
    );

    expect(described.title).toBe(title);
    expect(described.detail.startsWith('Time: ')).toBe(true);
    expect(described.detail).toContain('10/20/2026');
    expect(described.actor).toBe('Customer');
  });

  it('says a failed notice was recorded by the system, not the customer', () => {
    const described = describeActivity(
      activity(1, 'booking_notice_failed', {
        meeting_id: 9,
        starts_at: '2026-10-20T13:00:00Z',
        by: 'system',
        kind: 'day_before',
        reason: 'template_required',
      })
    );

    expect(described.title).toBe('WhatsApp notice did not go out');
    // Qual aviso e por quê, em palavras leigas; erro de envio sem motivo conhecido vira "Falhou".
    expect(described.detail.startsWith('1 day before: ')).toBe(true);
    expect(described.detail).not.toContain('template_required');
    expect(described.actor).toBe('System');

    const crashed = describeActivity(
      activity(2, 'booking_notice_failed', {
        meeting_id: 9,
        starts_at: '2026-10-20T13:00:00Z',
        by: 'system',
        kind: 'booked',
        reason: 'Net::ReadTimeout',
      })
    );
    expect(crashed.detail).not.toContain('Net::');
  });

  it('shows from and to when the customer changes the time', () => {
    const { title, detail } = describeActivity(
      activity(1, 'booking_client_rescheduled', {
        meeting_id: 9,
        starts_at: '2026-10-21T13:00:00Z',
        from: '2026-10-20T13:00:00Z',
        by: 'client',
      })
    );

    expect(title).toBe('Customer changed the time');
    expect(detail.startsWith('From 10/20/2026')).toBe(true);
    expect(detail).toContain(' to 10/21/2026');
  });

  it('has the pt_BR copy for the booking activities', () => {
    const ptBR = { locale: 'pt_BR' };

    expect(
      t('CRM_KANBAN.DRAWER.ACTIVITY_BOOKING_CLIENT_CONFIRMED', {}, ptBR)
    ).toBe('Cliente confirmou o horário');
    expect(t('CRM_KANBAN.DRAWER.CLIENT_ACTOR', {}, ptBR)).toBe('Cliente');
  });

  it('does not use the cadence touch as an attempt counter on a sent AI follow-up', () => {
    const { detail } = describeActivity(
      activity(1, 'ai_followup_sent', { touch: 2 })
    );

    expect(detail).toBe('');
  });
  // #1196 (J6-A4): the meeting the AI booked is identifiable on the card.
  it('says the AI booked the meeting, and only for AI bookings', () => {
    const byAi = activity(1, 'meeting_scheduled', {
      title: 'Conversa de 30 min',
      source: 'ai',
    });
    const byLink = activity(2, 'meeting_scheduled', {
      title: 'Conversa de 30 min',
      source: 'public_link',
    });

    expect(describeActivity(byAi).detail).toBe(
      'Set by the assistant: Conversa de 30 min'
    );
    expect(describeActivity(byLink).detail).not.toContain('assistant');
  });
});

// #1498 — funil de Atender: os títulos próprios de Atender vêm antes.
describe('useCardHistorico — funil de Atender', () => {
  it('says "Request reopened" and "request details" instead of deal', () => {
    const atender = ref(true);
    const { describeActivity: descrever } = useCardHistorico({
      t,
      te,
      locale: ref('en'),
      activities: ref([]),
      textos: () =>
        atender.value
          ? ['CRM_CARD.HISTORICO.EVENTO_ATENDER', 'CRM_CARD.HISTORICO.EVENTO']
          : ['CRM_CARD.HISTORICO.EVENTO'],
    });
    const reabriu = activity(1, 'reopen', {});
    const mudou = activity(2, 'update', {});

    expect(descrever(reabriu).title).toBe('Request reopened');
    expect(descrever(mudou).title).toBe('The request details changed');
    expect(descrever(activity(3, 'move', {})).title).toBe(
      t('CRM_CARD.HISTORICO.EVENTO.ACTIVITY_MOVE')
    );

    atender.value = false;
    expect(descrever(reabriu).title).toBe(
      t('CRM_KANBAN.DRAWER.ACTIVITY_REOPEN')
    );
  });
});

// #1922: o card que a IA arquivou como "não é negócio" mostra a IA como autora
// e o motivo em texto nosso; o arquivamento à mão continua do jeito de sempre.
describe('useCardHistorico — card arquivado pela IA', () => {
  const REASONING = 'Fornecedor oferecendo serviço';

  it('shows the AI as the actor and the reason in our own words', () => {
    const arquivou = activity(1, 'archive', {
      by: 'ai',
      motivo: 'fora_do_negocio',
      confidence: 0.9,
      reasoning: REASONING,
    });
    const item = describeActivity(arquivou);

    expect(item.actor).toBe(t('CRM_CARD.HISTORICO.EVENTO.AI_ACTOR'));
    expect(item.detail).toBe(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_NAO_E_NEGOCIO')
    );
    expect(item.detail).not.toContain(REASONING);
  });

  it('names a repeated card', () => {
    const repetido = activity(1, 'archive', { by: 'ai', motivo: 'duplicado' });

    expect(describeActivity(repetido).detail).toBe(
      t('CRM_KANBAN.DRAWER.ACTIVITY_DETAIL_DUPLICADO')
    );
  });

  it('keeps a manual archive as before', () => {
    const aMao = activity(
      1,
      'archive',
      {},
      { actor_type: 'user', actor_name: 'Ana' }
    );
    const item = describeActivity(aMao);

    expect(item.actor).toBe('Ana');
    expect(item.detail).toBe('');
  });
});

// #2509: o movimento feito por automação aparece como da automação, não da
// pessoa que a ligou nem do "sistema"; quem ligou fica em texto menor.
describe('useCardHistorico — movimento feito por automação', () => {
  const movimento = (payload, extra = {}) =>
    activity(
      1,
      'move',
      { from_stage_id: 1, to_stage_id: 2, ...payload },
      { labels: { from_stage_id: 'Novo', to_stage_id: 'Proposta' }, ...extra }
    );

  it('shows the free automation with its name, who turned it on and a link', () => {
    const item = describeActivity(
      movimento(
        { by: 'automacao', origem: 'livre', automacao_id: 7 },
        {
          actor_type: 'user',
          actor_name: 'Ana',
          automacao: {
            origem: 'livre',
            id: 7,
            nome: 'Boas-vindas',
            pode_abrir: true,
          },
        }
      )
    );

    expect(item.actor).toBe('Automation «Boas-vindas»');
    expect(item.ligadaPor).toBe('turned on by Ana');
    expect(item.automacaoLink).toEqual({
      name: 'automacoes_livre_editar',
      params: { id: 7 },
    });
  });

  it('shows the rule and the stage automation instead of "System"', () => {
    const regra = describeActivity(
      movimento(
        { by: 'automacao', origem: 'regra', automacao_id: 3 },
        {
          automacao: {
            origem: 'regra',
            id: 3,
            nome: 'Regra do lead',
            pode_abrir: false,
          },
        }
      )
    );
    const etapa = describeActivity(
      movimento(
        { by: 'automacao', origem: 'etapa', automacao_id: 4 },
        {
          automacao: {
            origem: 'etapa',
            id: 4,
            nome: 'Entrou na proposta',
            pode_abrir: false,
          },
        }
      )
    );

    expect(regra.actor).toBe('Automation «Regra do lead»');
    expect(regra.automacaoLink).toBeNull();
    expect(regra.ligadaPor).toBe('');
    expect(etapa.actor).toBe('Automation «Entrou na proposta»');
    expect(etapa.automacaoLink).toBeNull();
  });

  // Na de etapa e na regra, o ator é quem moveu o card ou disparou o evento, e
  // não quem ligou a automação: a linha não pode dizer que essa pessoa a ligou.
  it('does not say who turned on a stage automation or a rule', () => {
    const comPessoa = origem =>
      describeActivity(
        movimento(
          { by: 'automacao', origem, automacao_id: 4 },
          {
            actor_type: 'user',
            actor_name: 'Bruno',
            automacao: { origem, id: 4, nome: 'Entrou', pode_abrir: false },
          }
        )
      );

    expect(comPessoa('etapa').actor).toBe('Automation «Entrou»');
    expect(comPessoa('etapa').ligadaPor).toBe('');
    expect(comPessoa('regra').ligadaPor).toBe('');
  });

  it('says "An automation" when the automation no longer exists', () => {
    const item = describeActivity(
      movimento(
        { by: 'automacao', origem: 'livre', automacao_id: 9 },
        {
          automacao: { origem: 'livre', id: 9, nome: null, pode_abrir: false },
        }
      )
    );

    expect(item.actor).toBe('An automation');
    expect(item.automacaoLink).toBeNull();
  });

  it('keeps a move made by a person as before', () => {
    const item = describeActivity(
      movimento({}, { actor_type: 'user', actor_name: 'Ana', automacao: null })
    );

    expect(item.actor).toBe('Ana');
    expect(item.ligadaPor).toBe('');
    expect(item.automacaoLink).toBeNull();
  });
});

// #2501: o pedido da API sem uma etapa do funil põe o card na etapa de entrada
// dele, e o histórico diz por quê.
describe('useCardHistorico — etapa de entrada do funil', () => {
  const labels = { from_stage_id: 'Novo Lead', to_stage_id: 'Entrada' };

  it('says the card went to the entry stage because the request had no stage', () => {
    const item = describeActivity(
      activity(
        1,
        'move',
        {
          from_stage_id: 1,
          to_stage_id: 2,
          motivo: 'etapa_nao_veio',
          to_pipeline_name: 'Pós-venda',
        },
        { labels }
      )
    );

    expect(item.detail).toBe(
      'Moved to Pós-venda › Entrada (the stage was not in the request)'
    );
  });

  it('says the stage in the request was from another pipeline', () => {
    const item = describeActivity(
      activity(
        1,
        'move',
        {
          to_stage_id: 2,
          motivo: 'etapa_de_outro_funil',
          to_pipeline_name: 'Pós-venda',
        },
        { labels }
      )
    );

    expect(item.detail).toBe(
      'Moved to Pós-venda › Entrada (the stage in the request is not from this pipeline)'
    );
  });

  it('says where a card created without a stage was placed', () => {
    const item = describeActivity(
      activity(
        1,
        'create',
        { stage_id: 2, motivo: 'etapa_nao_veio', pipeline_name: 'Pós-venda' },
        { labels: { stage_id: 'Entrada' } }
      )
    );

    expect(item.detail).toBe(
      'Created in Pós-venda › Entrada (the stage was not in the request)'
    );
  });

  it('keeps the usual move text without the pipeline name', () => {
    const item = describeActivity(
      activity(
        1,
        'move',
        { from_stage_id: 1, to_stage_id: 2, motivo: 'etapa_nao_veio' },
        { labels }
      )
    );

    expect(item.detail).toBe('From Novo Lead to Entrada');
  });
});
