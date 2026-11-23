# #3099: o bloco "Duas versões da mensagem" do resultado da campanha (GET …/campaign_journey/results/:channel/:id), no
# formato que a tela lê (CampaignResult/ResultDuasVersoes.vue):
#
#   { estado, criterio, escolhe_em (epoch), vencedora, escolhida_por, escolhida_em (epoch), resto,
#     versoes: [{ numero, texto, receberam, responderam, compraram, valor: [{ currency, cents }] | nil }] }
#
# nil quando a campanha não tem duas versões. O valor em R$ só vai para quem vê valor de venda (Crm::ValorDeVenda), e
# as compras só contam os funis que a pessoa vê nos relatórios (#1148), como o resto do resultado (F2).
class CampaignJourney::DuasVersoes::Resultado
  def initialize(link, account:)
    @link = link
    @account = account
  end

  def payload(user:, account_user:)
    return unless CampaignJourney::DuasVersoes.new(@link).ativo?

    numeros = CampaignJourney::DuasVersoes::Numeros.new(@link, account: @account)
    contas = numeros.por_versao(pipeline_ids: funis_visiveis(user, account_user), com_valor: Crm::ValorDeVenda.ve?(account_user))
    {
      estado: @link.teste_estado, criterio: @link.teste_criterio, escolhe_em: escolhe_em(numeros)&.to_i,
      vencedora: @link.teste_vencedora, escolhida_por: @link.teste_escolhida_por, escolhida_em: @link.teste_escolhida_em&.to_i,
      resto: @link.teste_resto, versoes: textos.each_with_index.map { |texto, indice| { numero: indice + 1, texto: texto, **contas[indice] } }
    }
  end

  private

  # Gravada pelo cron quando o teste começa a sair; antes disso, a previsão pelo primeiro envio (ou pelo agendamento).
  def escolhe_em(numeros)
    return @link.teste_escolhe_em if @link.teste_escolhe_em

    inicio = numeros.primeiro_envio || agendada_para
    inicio && (inicio + @link.teste_espera_horas.hours)
  end

  def agendada_para
    @link.campaign.try(:scheduled_at)
  end

  def funis_visiveis(user, account_user)
    visible = Crm::Access::VisiblePipelines.new(user: user, account: @account, account_user: account_user)
    visible.report_ids if visible.restricted?
  end

  # [texto da versão 1, texto da versão 2]: a mensagem, o corpo do modelo ou o assunto, como cada canal guarda.
  def textos
    campaign = @link.campaign
    segunda = @link.segunda_versao.to_h
    case campaign
    when EmailCampaign then [campaign.subject.to_s, segunda['subject'].to_s]
    when WhatsappApiCampaign then [campaign.message_body.to_s, segunda['message_body'].to_s]
    else [campaign.message.to_s, (segunda['message'] || segunda['message_body']).to_s]
    end
  end
end
