# A renovação de UMA conta (E5, #2898): cria o card de cada seguro que entra em renovação hoje
# (Carteira::Renovacao::EntramHoje), no funil e na etapa que a conta escolheu. Não faz nada na conta sem a carteira, sem
# o CRM, sem escolha, ou com o funil arquivado (Carteira::RenovacaoConfig#escolhida?): nada vira card até alguém
# escolher um funil ativo.
#
# Rodar de novo é seguro: quem já tem card não entra (e o CriarCard confere sob a trava). Por isso não há nova
# tentativa: a próxima passada da rotina, em uma hora, é a nova tentativa.
#
# Falha num seguro vai para o log (a classe do erro, nunca a mensagem, que pode trazer dado do cliente) e não para os
# outros. No fim, o job falha com o primeiro erro, para aparecer no Sidekiq.
class Carteira::Renovacao::DaContaJob < ApplicationJob
  queue_as :scheduled_jobs
  sidekiq_options retry: false

  def perform(account_id)
    account = Account.find_by(id: account_id)
    config = account && Carteira::RenovacaoConfig.find_by(account_id: account.id)
    return unless config && pode_criar?(account, config)

    nasceram, erro = criar_cards(account, config)
    Rails.logger.info("[carteira][renovacao] conta=#{account.id} cards=#{nasceram}") if nasceram.positive?
    avisar(account, config) if nasceram.positive?
    raise erro if erro
  end

  private

  # O aviso no sino conta os seguros que entraram em renovação hoje. Se ele falhar, os cards já nasceram: fica no log.
  def avisar(account, config)
    Carteira::Aviso.new(account, config).entraram
  rescue StandardError => e
    Rails.logger.error("[carteira][renovacao] aviso não saiu conta=#{account.id} #{e.class}")
  end

  def pode_criar?(account, config)
    Crm::Config.enabled? && Carteira::Acesso.liberada?(account) && config.escolhida?
  end

  # [quantos cards nasceram, o primeiro erro]. A conta do emissor do CRM é lembrada pelo lote inteiro (EmLote).
  def criar_cards(account, config)
    criar = Carteira::Renovacao::CriarCard.new(account, config)
    nasceram = 0
    erro = nil
    Autonomia::Automacao::EmLote.durante do
      Carteira::Renovacao::EntramHoje.new(account, dias_antes: config.dias_antes).cada do |apolice|
        nasceram += 1 if criar.call(apolice)
      rescue StandardError => e
        erro ||= e
        Rails.logger.error("[carteira][renovacao] card não nasceu conta=#{account.id} seguro=#{apolice.id} #{e.class}")
      end
    end
    [nasceram, erro]
  end
end
