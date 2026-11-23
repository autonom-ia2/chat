# #3099: o teste das duas versões em que ninguém recebeu nada (todos pulados, canal desligado, falta de variável,
# campanha parada). Sem envio não há hora de escolher (ela sai do primeiro envio), e o resto ficaria esperando para
# sempre, sem ninguém saber. Então:
# - depois da espera da regra, contada do começo do teste, o Resultado e a lista de Campanhas avisam (#avisar?);
# - depois de PRAZO_SEM_ENVIO, a versão 1 vai para o resto ('sem_envio', CampaignJourney::DuasVersoes::Escolha): a
#   campanha segue como uma campanha comum, e cada pessoa passa pelas mesmas conferências do envio.
# O começo do teste é o sorteio (as linhas do teste) ou o agendamento da campanha, o que for depois.
class CampaignJourney::DuasVersoes::SemEnvio
  def initialize(link, agora: Time.current)
    @link = link
    @agora = agora
  end

  # Testando, já começou e ninguém do teste recebeu.
  def sem_envio?
    return @sem_envio if defined?(@sem_envio)

    @sem_envio = @link.teste_estado == 'testando' && comeco.present? && comeco <= @agora &&
                 CampaignJourney::DuasVersoes::Numeros.new(@link, account: @link.account).primeiro_envio.nil?
  end

  def avisar?
    sem_envio? && comeco + @link.teste_espera_horas.hours <= @agora
  end

  # Quando a versão 1 vai sozinha para o resto.
  def ate
    comeco + CampaignJourney::DuasVersoes::PRAZO_SEM_ENVIO if sem_envio?
  end

  def venceu?
    sem_envio? && ate <= @agora
  end

  private

  def comeco
    return @comeco if defined?(@comeco)

    sorteio = CampaignVersionContact.where(campaign_audience_link_id: @link.id, fase: 'teste').minimum(:created_at)
    @comeco = [sorteio, @link.campaign.try(:scheduled_at)].compact.max
  end
end
