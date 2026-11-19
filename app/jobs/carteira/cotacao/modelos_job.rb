# Pede à Meta os 2 modelos da cotação da renovação (#3055, E8 #2901): o "Algo mudou?" e a proposta
# (Carteira::Cotacao::Modelos::FINALIDADES), na caixa que a conta escolheu em Ajustar renovações. Fora da requisição,
# porque fala com a Meta. Molde: Crm::BookingV2::NoticeTemplateEnsureJob, do Agendamento.
#
# Quem enfileira e quando o sistema pode pedir estão em Carteira::Cotacao::Modelos: a cotação aberta na conta, a caixa
# do WhatsApp oficial Cloud e o Aviso de serviço ligado. Tudo é relido aqui, na hora de rodar. O `Garantir` não duplica
# pelo nome e não recria o que está em análise, então repetir o job é seguro.
#
# Cada resultado vai ao log (status e motivo, sem texto nem dado de cliente). Erro numa finalidade vai ao tracker e não
# para a outra. Meta fora do ar: a finalidade que falta fica para depois (não insiste na Meta caída) e o job tenta de
# novo mais tarde (o que já foi criado volta "em análise" pela lista da caixa, sem falar com a Meta). Esgotadas as
# tentativas: log e tracker.
class Carteira::Cotacao::ModelosJob < ApplicationJob
  class MetaFora < StandardError; end

  LOG = Carteira::Cotacao::Modelos::LOG
  META_FORA = 'meta_fora'.freeze

  queue_as :low

  # A mensagem do erro só leva ids (conta e caixa), nunca dado de cliente.
  retry_on MetaFora, wait: 5.minutes, attempts: 3 do |job, error|
    Rails.logger.warn("#{LOG} desistiu #{error.message} motivo=#{META_FORA}")
    ChatwootExceptionTracker.new(error, account: Account.find_by(id: job.arguments.first)).capture_exception
  end

  def perform(account_id)
    caixa = Carteira::Cotacao::Modelos.caixa(Carteira::RenovacaoConfig.find_by(account_id: account_id))
    return if caixa.nil?

    raise MetaFora, "account_id=#{caixa.account_id} inbox_id=#{caixa.id}" unless garantir_caixa(caixa)
  end

  private

  # Falso quando a Meta caiu: o `none?` para na primeira finalidade com `meta_fora`.
  def garantir_caixa(caixa)
    Carteira::Cotacao::Modelos::FINALIDADES.none? { |finalidade| garantir(caixa, finalidade).to_h[:motivo] == META_FORA }
  end

  def garantir(caixa, finalidade)
    resultado = Whatsapp::Templates::Garantir.call(inbox: caixa, finalidade: finalidade, criar: true)
    Rails.logger.info("#{LOG} account_id=#{caixa.account_id} inbox_id=#{caixa.id} finalidade=#{finalidade} " \
                      "status=#{resultado[:status]} motivo=#{resultado[:motivo] || '-'}")
    resultado
  rescue StandardError => e
    Rails.logger.error("#{LOG} erro account_id=#{caixa.account_id} inbox_id=#{caixa.id} finalidade=#{finalidade} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: caixa.account).capture_exception
    nil
  end
end
