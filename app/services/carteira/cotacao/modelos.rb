# Os 2 modelos da Meta que a cotação da renovação manda ao segurado (#3055, E8 #2901): o "Algo mudou?"
# (`renovacao_algo_mudou`) e a proposta (`renovacao_proposta`). O `Carteira::Cotacao::Envio` só LÊ a lista da caixa
# (`criar: false`); quem pede os 2 à Meta é o `Carteira::Cotacao::ModelosJob`, fora da requisição, no molde do
# `Crm::BookingV2::NoticeTemplateEnsureJob` do Agendamento (aprovado pelo Rodrigo em 19/11).
#
# O sistema só pede quando a conta pode mandar (`caixa`): a cotação aberta (Carteira::Cotacao.aberta?: carteira, chave
# da cotação e quem cota), a caixa escolhida em Ajustar renovações sendo WhatsApp oficial Cloud (`MetaClient.supported?`)
# e o Aviso de serviço ligado pelo dono (`WhatsappTemplateConsent`, marca `utility`). Os 2 prontos são de UTILIDADE
# (`Finalidades::CATEGORIA`, a categoria padrão do pronto), e é com essa marca que o `Garantir` deixa criar.
#
# Quem enfileira o job:
# - `pedir`: salvar os ajustes da renovação mudando a caixa ou quem cota (Carteira::Renovacao::SalvarAjustes);
# - o dono ligar o Aviso de serviço (`whatsapp_templates.consentimento_ligado`, initializer
#   `whatsapp_templates_consentimento_ligado.rb`);
# - `curar`: a autocura do envio. O modelo fora da lista da caixa (`ausente`) com tudo acima liberado quer dizer que o
#   gatilho se perdeu (a chave da cotação ligada direto no banco, por exemplo). Enfileira no máximo 1 vez a cada 15 min
#   por caixa (trava `SET NX EX` no Redis), como a autocura do Agendamento (Crm::BookingV2::Notices::Route). O envio
#   daquele momento não espera: continua `sem_modelo`.
#
# Erro ao enfileirar nunca derruba quem chamou (o ajuste já foi gravado, o envio já tem o motivo dele): vai ao log (só a
# classe) e ao tracker. Na autocura, o erro tira a trava, para o próximo envio tentar de novo.
module Carteira::Cotacao::Modelos
  FINALIDADES = %w[renovacao_algo_mudou renovacao_proposta].freeze
  CONSENTIMENTO = :utility
  LOG = '[carteira][cotacao][modelos]'.freeze
  CURA_TRAVA = 'carteira:cotacao:modelos_cura:%<inbox_id>d'.freeze
  CURA_VALIDADE = 15.minutes.to_i

  module_function

  # A caixa em que o sistema pode pedir os modelos agora, ou nil.
  def caixa(config)
    return if config.nil? || !Carteira::Cotacao.aberta?(config.account, config)

    inbox = config.inbox
    return unless inbox && Whatsapp::Templates::MetaClient.supported?(inbox)

    inbox if WhatsappTemplateConsent.ativo?(config.account, CONSENTIMENTO)
  end

  def pedir(config)
    return if caixa(config).nil?

    Carteira::Cotacao::ModelosJob.perform_later(config.account_id)
  rescue StandardError => e
    Rails.logger.error("#{LOG} nao_enfileirado account_id=#{config.account_id} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: config.account).capture_exception
  end

  # resultado: o do `Garantir` com `criar: false`. As condições vêm antes da trava, para não gastá-la.
  def curar(config, resultado)
    return unless resultado[:status] == :indisponivel && resultado[:motivo] == 'ausente'

    inbox = caixa(config)
    return if inbox.nil?

    trava = format(CURA_TRAVA, inbox_id: inbox.id)
    return unless Redis::Alfred.set(trava, 1, nx: true, ex: CURA_VALIDADE)

    enfileirar_cura(config, trava)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: config.account).capture_exception
  end

  def enfileirar_cura(config, trava)
    Carteira::Cotacao::ModelosJob.perform_later(config.account_id)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: config.account).capture_exception
    Redis::Alfred.delete(trava)
  end
  private_class_method :enfileirar_cura
end
