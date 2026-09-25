# Trava por empresa da pesquisa (#679): duas pesquisas simultâneas do mesmo lugar fazem uma chamada paga só.
#
# Trava de sessão do Postgres, sem transação nem trava de linha durante a chamada de rede (mesmo desenho de
# EmailCampaigns::Reputation::CampaignDeliveryLock). Quem não pega a trava não espera segurando conexão: volta como
# waiting_capacity e o job tenta de novo, quando o resultado da primeira já está gravado para reaproveitar.
#
# A chave é o lugar (provider + id do lugar), igual em qualquer conta. Sem id do lugar, o lead é a própria chave.
module Autonomia::Prospecting::Research::CompanyLock
  NAMESPACE = 679
  PREFIX = 'prospecting_research:'.freeze

  module_function

  def key_for(lead)
    return "place:#{lead.provider}:#{lead.provider_place_id}" if lead.provider_place_id.present?

    "lead:#{lead.id}"
  end

  # true quando a trava foi pega e o bloco rodou; false quando outra pesquisa da mesma empresa está rodando.
  def synchronize(lead)
    ActiveRecord::Base.connection_pool.with_connection do |connection|
      key = connection.quote("#{PREFIX}#{key_for(lead)}")
      return false unless connection.select_value("SELECT pg_try_advisory_lock(#{NAMESPACE}, hashtext(#{key}))")

      begin
        yield
      ensure
        connection.select_value("SELECT pg_advisory_unlock(#{NAMESPACE}, hashtext(#{key}))")
      end
      true
    end
  end
end
