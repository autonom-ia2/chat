# Uma campanha do WhatsApp Oficial ou do SMS manda por um caminho de cada vez: a retomada dos adiados
# (CampaignJourney::RetomarAdiadosJob, #3063) e o resto das duas versões (CampaignJourney::DuasVersoes::EnvioDoResto,
# #3099) pegam os mesmos destinatários na fila; rodando juntos, a mesma pessoa receberia duas vezes. A trava é um
# advisory lock do Postgres por campanha, sem espera: quem chega com a trava tomada não roda e devolve false.
module CampaignJourney::EnvioSozinho
  module_function

  def sozinho(campaign)
    chave = "campaign_journey:retomar_adiados:#{campaign.id}"
    conexao = ActiveRecord::Base.connection
    return false unless conexao.select_value("SELECT pg_try_advisory_lock(hashtextextended(#{conexao.quote(chave)}, 0))")

    begin
      yield
      true
    ensure
      conexao.select_value("SELECT pg_advisory_unlock(hashtextextended(#{conexao.quote(chave)}, 0))")
    end
  end
end
