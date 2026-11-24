# "Mandar de novo" (#3101) no resultado da primeira campanha (ResultsController#show, `segunda_mensagem`). Nil quando a
# campanha não tem segunda mensagem. Senão:
#   { status, dias, quem, previsto_em, campanha }
# - status: o `reenvio_status` (aguardando, enviado, sem_ninguem, cancelado, falhou — CampaignJourney::Reenvio);
# - previsto_em: quando ela sai (`reenvio_em`, epoch), nulo até a primeira terminar de sair;
# - campanha: a campanha que ela gerou (só no enviado), com o endereço do resultado dela e os números pela mesma régua do
#   resultado: receberam = Enviadas (no e-mail, Entregues); responderam = Responderam (a marca da campanha,
#   CampaignJourney::ReplyMarker). Nula quando a campanha nova foi apagada (ou não é desta conta: vai para o log).
class CampaignJourney::Reenvio::Resultado
  def initialize(campanha, account:)
    @campanha = campanha
    @account = account
  end

  def payload
    opcoes = Autonomia::CampanhaOpcoesDeEnvio.find_by(account_id: @account.id, campanha: @campanha)
    return if opcoes&.reenvio_status.blank?

    { status: opcoes.reenvio_status, dias: opcoes.reenvio_dias, quem: opcoes.reenvio_quem, previsto_em: opcoes.reenvio_em&.to_i,
      campanha: campanha_payload(opcoes) }
  end

  private

  def campanha_payload(opcoes)
    return unless opcoes.reenvio_status == CampaignJourney::Reenvio::ENVIADO

    resultado = resultado_de(opcoes.reenvio_campanha)
    return if resultado.nil?

    totais = resultado.totals
    campanha = resultado.campaign_payload
    { channel: campanha[:channel], id: campanha[:id], name: campanha[:name], processing: saindo?(resultado, campanha),
      receberam: resultado.is_a?(CampaignJourney::EmailResult) ? totais[:delivered] : totais[:sent], responderam: totais[:replied] }
  end

  # Ainda saindo: o resultado dela diz que está enviando ou, no WhatsApp Oficial e no SMS, ela ainda não começou. A
  # varredura grava `enviado` logo que a cria, e a Campaign nasce `active`: só vira `processing` quando o envio começa
  # (Campaign#mark_processing!). Sem isto a tela mostrava "0 receberam" sem dizer que ela ainda vai sair.
  def saindo?(resultado, campanha)
    campanha[:processing] || (resultado.campaign.is_a?(Campaign) && resultado.campaign.active?)
  end

  # O resultado da campanha nova pelo mesmo endereço da tela dele (CampaignJourney::ResultFinder), só dentro da conta.
  def resultado_de(nova)
    return if nova.nil?

    # Na conta antes de achar: WhatsApp Oficial e SMS são achados pelo display_id, que se repete entre contas.
    return sem_a_campanha_nova(nova) unless nova.account_id == @account.id

    finder = CampaignJourney::ResultFinder.new(@account)
    case nova
    when EmailCampaign then finder.find!(CampaignJourney::ResultFinder::EMAIL, nova.id)
    when WhatsappApiCampaign then finder.find!(CampaignJourney::ResultFinder::WHATSAPP_API, nova.id)
    else finder.find!(CampaignJourney::ResultFinder.channel_of(nova).to_s, nova.display_id)
    end
  rescue ActiveRecord::RecordNotFound
    sem_a_campanha_nova(nova)
  end

  def sem_a_campanha_nova(nova)
    Rails.logger.warn("[CampaignJourney::Reenvio] resultado sem a campanha nova #{nova.class.name}##{nova.id} na conta #{@account.id}")
    nil
  end
end
