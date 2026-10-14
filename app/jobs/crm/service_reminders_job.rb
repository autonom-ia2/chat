# Lembretes de Atender (#1498): a cada 15 minutos, cria os lembretes por data que venceram ou vão vencer e cancela os
# que deixaram de valer (Crm::FollowUps::ServiceReminderScheduler). Quem manda é o Crm::FollowUpDueJob, de minuto em
# minuto. Só funil de Atender com algum interruptor ligado; um card com problema não para os outros.
#
# Ligar o interruptor num funil cheio de cards parados não pode virar uma rajada de mensagens de IA (custo e incômodo
# ao cliente): cada rodada cria no máximo MAX_NOVOS_POR_FUNIL lembretes por funil, espaçados de STAGGER; o resto
# fica para as rodadas seguintes.
class Crm::ServiceRemindersJob < ApplicationJob
  queue_as :scheduled_jobs

  # Resolvido há mais tempo que isto já não ganha "deu tudo certo?".
  RESOLVED_LOOKBACK = Crm::FollowUps::ServiceReminderScheduler::RESOLVED_CHECK_WINDOW
  MAX_NOVOS_POR_FUNIL = 20
  PRELOAD = [:account, :stage, :contact, :owner, { primary_conversation: [:inbox, :contact] }].freeze

  def perform(now: Time.current)
    return unless Crm::Ai::Config.enabled?

    Crm::Pipeline.active.where(counts_as_sale: false).find_each { |pipeline| schedule_pipeline(pipeline, now) }
  end

  private

  def schedule_pipeline(pipeline, now)
    settings = Crm::Ai::Config.service_reminders_settings(pipeline)
    opcoes = { now: now, settings: settings, schedule_config: Crm::Ai::Config.auto_followup_settings(pipeline) }
    novos = 0
    cards_for(pipeline, now, settings).find_each do |card|
      break if novos >= MAX_NOVOS_POR_FUNIL

      card.association(:pipeline).target = pipeline
      novos += schedule(card, opcoes.merge(atraso: novos * Crm::FollowUps::ServiceReminderScheduler::STAGGER))
    end
  end

  # Com tudo desligado, ainda passa pelos cards que têm lembrete pendente, para cancelá-los.
  def cards_for(pipeline, now, settings)
    scope = pipeline.cards.where(status: :open).or(pipeline.cards.where(status: :resolved, closed_at: (now - RESOLVED_LOOKBACK)..))
                    .includes(*PRELOAD)
    return scope if settings.values.any?

    scope.where(id: pending_card_ids(pipeline))
  end

  def pending_card_ids(pipeline)
    Crm::FollowUp.active.where(account_id: pipeline.account_id)
                 .where("metadata ->> 'source' = ?", Crm::FollowUps::ServiceReminderScheduler::SOURCE)
                 .where(card_id: pipeline.cards.select(:id)).select(:card_id)
  end

  def schedule(card, opcoes)
    Crm::FollowUps::ServiceReminderScheduler.new(card: card, **opcoes).perform
  rescue StandardError => e
    Rails.logger.error("[crm][service_reminders] card_id=#{card.id} error_class=#{e.class.name} message=#{e.message.to_s[0, 160]}")
    0
  end
end
