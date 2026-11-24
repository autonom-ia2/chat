# #3099: a decisão do cron (CampaignJourney::EscolherVencedoraJob) para uma campanha com duas versões cujo resto espera.
#
# 1. Grava `teste_escolhe_em` quando o teste começa a sair: primeiro envio + espera (a campanha pode ter sido agendada,
#    ou o limite por cliente pode ter atrasado o começo).
# 2. Na hora, com critério automático (respostas ou compras): a melhor pela régua da tela
#    (CampaignJourney::DuasVersoes::Vencedora) vai para o resto; empate ou poucas respostas, a versão 1 ('empate').
# 3. "Eu escolho": na hora vira 'esperando_voce' (a tela pede a escolha e a lista de Campanhas avisa). D5: sem ninguém
#    escolher, depois de PRAZO_DO_EU_ESCOLHO a versão 1 vai sozinha ('sistema').
# 4. Ninguém do teste recebeu (sem primeiro envio, não há hora): depois de PRAZO_SEM_ENVIO a versão 1 vai para o resto
#    ('sem_envio', CampaignJourney::DuasVersoes::SemEnvio). Antes disso, o Resultado e a lista de Campanhas avisam.
class CampaignJourney::DuasVersoes::Escolha
  def initialize(link, agora: Time.current)
    @link = link
    @agora = agora
    @versoes = CampaignJourney::DuasVersoes.new(link)
  end

  def decidir!
    return unless @versoes.esperando_o_resto?

    hora = hora_de_escolher
    return sem_envio if hora.nil?
    return if hora > @agora
    return eu_escolho(hora) if @link.teste_criterio == 'eu_escolho'

    melhor = CampaignJourney::DuasVersoes::Vencedora.melhor(*numeros.por_versao, @link.teste_criterio)
    melhor ? @versoes.mandar_resto!(melhor, por: :sistema) : @versoes.mandar_resto!(1, por: :empate)
  end

  private

  def sem_envio
    @versoes.mandar_resto!(1, por: :sem_envio) if CampaignJourney::DuasVersoes::SemEnvio.new(@link, agora: @agora).venceu?
  end

  def eu_escolho(hora)
    return @versoes.esperar_voce! if @link.teste_estado == 'testando'

    @versoes.mandar_resto!(1, por: :sistema) if hora + CampaignJourney::DuasVersoes::PRAZO_DO_EU_ESCOLHO <= @agora
  end

  def hora_de_escolher
    return @link.teste_escolhe_em if @link.teste_escolhe_em

    inicio = numeros.primeiro_envio
    return if inicio.nil?

    @link.update!(teste_escolhe_em: inicio + @link.teste_espera_horas.hours)
    @link.teste_escolhe_em
  end

  def numeros
    @numeros ||= CampaignJourney::DuasVersoes::Numeros.new(@link, account: @link.account)
  end
end
