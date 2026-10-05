# E-mail result of a journey campaign (#999, acceptance E1): every recipient falls in exactly one
# of three groups, so Entregues + Voltaram + Não enviados = Público elegível (recipients_count).
#
#   voltaram     — status bounced;
#   entregues    — not bounced and accepted by the provider (sent_at present: delivered, opened,
#                  clicked, later unsubscribed/complained, or only accepted);
#   nao_enviados — not bounced and never accepted (suppressed, failed, canceled, still pending).
#
# The "elegível" audience is the list written from the audience (CampaignJourney::EmailAudienceRecipients),
# suppressed addresses included as "não enviados". The result screen (#1007) reads these numbers.
class CampaignJourney::EmailResultTotals
  def initialize(campaign)
    @campaign = campaign
  end

  def call
    bounced = EmailCampaignRecipient.statuses[:bounced]
    row = @campaign.email_campaign_recipients.pick(
      Arel.sql('COUNT(*)'),
      Arel.sql("COUNT(*) FILTER (WHERE status <> #{bounced} AND sent_at IS NOT NULL)"),
      Arel.sql("COUNT(*) FILTER (WHERE status = #{bounced})"),
      Arel.sql("COUNT(*) FILTER (WHERE status <> #{bounced} AND sent_at IS NULL)")
    )
    %i[eligible delivered bounced not_sent].zip(row).to_h
  end
end
