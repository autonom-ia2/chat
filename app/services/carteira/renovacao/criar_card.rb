# O card de renovação de um seguro (E5, #2898): nasce no funil e na etapa que a conta escolheu, ligado à pessoa do
# seguro, com o fim da vigência (o fim do dia, no fuso da conta) como data esperada. Quem cria é o sistema (sem autor),
# e a IA do funil respeita a etapa em que ele nasceu, como respeita a de uma automação (Crm::Ai::MovimentoDaAutomacao;
# `origem: 'carteira'`).
#
# Quem cuida do card é quem escolheu o funil nos ajustes, enquanto for da conta e ainda enxergar esse funil no quadro:
# o card sem dono e sem caixa só apareceria para o administrador. A história do seguro guarda com quem o card nasceu:
# o nome (`valores.cuida`) e o id (`valores.cuida_id`), que não muda quando o card troca de dono depois.
# Se essa pessoa saiu da conta, perdeu o CRM na função ou perdeu o funil no acesso por funil, o card nasce sem dono: com
# ela de dona, ele seria de quem não o abre.
#
# O passo da história (`renovacao_card_nasceu`, só deste card) guarda também o funil em que o card nasceu
# (`valores.funil`, o id): é por ele que a rotina sabe se o seguro ainda pode ganhar outro card nesta vigência
# (Carteira::Renovacao::EntramHoje).
#
# Um card por seguro. O seguro fica travado do começo ao fim e é relido sob a trava: duas passadas da rotina ao mesmo
# tempo não criam dois cards (o índice único de `crm_card_id` é a segunda barreira). O card, o vínculo e o passo da
# história entram juntos ou não entram. O título não leva dado da pessoa: só a seguradora.
class Carteira::Renovacao::CriarCard
  ORIGEM = 'carteira'.freeze
  NASCEU = 'renovacao_card_nasceu'.freeze

  def initialize(account, config)
    @account = account
    @config = config
    @dono = quem_escolheu_e_ainda_ve_o_funil
    @locale = account.locale.presence || I18n.default_locale
    @fuso = Crm::Timezone::Resolver.new(account: account).name_or_default
  end

  # true quando o card nasceu; false quando o seguro já não entra (outra passada chegou antes, ou ele ganhou desfecho).
  def call(apolice)
    apolice.with_lock(requires_new: true) do
      next false unless Carteira::Renovacao::EntramHoje.entra?(apolice)

      apolice.update!(crm_card: criar(apolice))
      apolice.eventos.create!(tipo: NASCEU, quando: Time.current, valores: do_nascimento)
      true
    end
  end

  private

  def do_nascimento
    { funil: @config.pipeline_id, cuida: @dono&.name, cuida_id: @dono&.id }.compact
  end

  # A mesma régua do quadro para pôr um card avulso num funil: ver o CRM (Crm::PipelinePolicy#index?) e ter o funil
  # entre os que a pessoa enxerga (Crm::Access::CardGuard#create_allowed?).
  def quem_escolheu_e_ainda_ve_o_funil
    conta_dela = @config.user_id && AccountUser.find_by(account_id: @account.id, user_id: @config.user_id)
    return unless conta_dela

    quem = { user: @config.user, account: @account, account_user: conta_dela }
    ve = Pundit.policy!(quem, Crm::Pipeline).index? && Crm::Access::CardGuard.new(**quem).create_allowed?(@config.pipeline_id, conversation: nil)
    @config.user if ve
  end

  def criar(apolice)
    Crm::Cards::Creator.new(account: @account, user: nil, params: do_card(apolice), automacao: { origem: ORIGEM, id: apolice.id }).perform
  end

  def do_card(apolice)
    { pipeline_id: @config.pipeline_id, stage_id: @config.stage_id, contact_id: apolice.contact_id, owner_id: @dono&.id,
      title: I18n.t('carteira.renovacao.card.titulo', seguradora: apolice.seguradora, locale: @locale),
      expected_close_at: apolice.fim_vigencia.in_time_zone(@fuso).end_of_day }
  end
end
