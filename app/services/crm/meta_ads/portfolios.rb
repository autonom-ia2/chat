# Portfólios da Meta que provam que uma conta de anúncios é desta conta do Chat2You (#1047).
#
# Vêm do WhatsApp oficial da conta: a verificação de saúde do número grava o portfólio dono do WABA
# (`phone_number_health['business_portfolio_id']`, lido da Graph, não digitado). Ficam de fora:
# - o portfólio da própria plataforma (parceira), que não pertence a cliente nenhum;
# - portfólio que aparece no WhatsApp de mais de uma conta do Chat2You, como o de um revendedor que
#   registrou os números de vários clientes no próprio portfólio. Ele não identifica um dono só.
class Crm::MetaAds::Portfolios
  HEALTH_KEY = 'business_portfolio_id'.freeze

  def self.for(account)
    own = ids_by_account.fetch(account.id, [])
    shared = ids_by_account.values.flatten.tally.select { |_id, count| count > 1 }.keys
    own - shared - [Crm::MetaAds::Platform.business_id].compact
  end

  # { account_id => [portfólio, ...] } de todos os WhatsApp oficiais, sem repetir dentro da conta.
  def self.ids_by_account
    Channel::Whatsapp.joins(:inbox).pluck('inboxes.account_id', Arel.sql("channel_whatsapp.phone_number_health ->> '#{HEALTH_KEY}'"))
                     .reject { |_account_id, id| id.blank? }
                     .group_by(&:first)
                     .transform_values { |rows| rows.map { |row| row.last.to_s }.uniq }
  end
end
