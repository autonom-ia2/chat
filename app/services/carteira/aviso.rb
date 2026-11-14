# O aviso da carteira no sino (E5, #2898): "N seguros entraram em renovação hoje". Um aviso por conta por dia, com a
# contagem, em vez de um por card: em carteira grande, um por card vira ruído. O número é o do dia inteiro (os cards que
# nasceram hoje, no dia da conta), e o aviso novo toma o lugar do anterior da mesma pessoa
# (Notification::RemoveDuplicateNotificationJob, pelo ator): se a rotina criar mais cards à tarde, a pessoa continua com
# um aviso só, com o total.
#
# Recebe quem pode ver a carteira (ver contatos), tem o CRM e enxerga o funil das renovações no quadro. Só no painel: sem
# e-mail nem push. O ator é a linha de ajustes da conta; o aviso leva só a contagem, nenhum dado de cliente. O aviso de uma
# pessoa que falhar não para os outros.
class Carteira::Aviso
  TIPO = 'carteira_renovacao'.freeze

  def initialize(account, config)
    @account = account
    @config = config
  end

  def entraram
    quantos = self.class.nasceram_hoje(@account)
    return if quantos.zero?

    quem_recebe.each do |pessoa|
      Notification.create!(notification_type: TIPO, user: pessoa, account: @account, primary_actor: @config, meta: { 'quantos' => quantos })
    rescue StandardError => e
      Rails.logger.error("[carteira][aviso] não saiu conta=#{@account.id} user=#{pessoa.id} #{e.class}")
    end
  end

  # Os cards de renovação que nasceram hoje, no dia da conta.
  def self.nasceram_hoje(account)
    fuso = Crm::Timezone::Resolver.new(account: account).name_or_default
    inicio = Carteira::Selo.hoje(account).in_time_zone(fuso).beginning_of_day
    Carteira::ApoliceEvento.joins(:apolice).where(carteira_apolices: { account_id: account.id })
                           .where(tipo: Carteira::Renovacao::CriarCard::NASCEU, quando: inicio..).count
  end

  private

  def quem_recebe
    @account.account_users.includes(:user).filter_map { |vinculo| vinculo.user if recebe?(vinculo) }
  end

  def recebe?(vinculo)
    de_quem = { user: vinculo.user, account: @account, account_user: vinculo }
    ContactPolicy.new(de_quem, Contact).index? && Crm::PipelinePolicy.new(de_quem, Crm::Pipeline).index? &&
      Crm::Access::VisiblePipelines.new(**de_quem).visible?(@config.pipeline_id)
  end
end
