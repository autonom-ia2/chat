# O card de renovação de um seguro (E5, #2898): nasce no funil e na etapa que a conta escolheu, ligado à pessoa do
# seguro, com o fim da vigência (o fim do dia, no fuso da conta) como data esperada. Quem cria é o sistema (sem autor):
# o card nasce sem dono, e a IA do funil respeita a etapa em que ele nasceu, como respeita a de uma automação
# (Crm::Ai::MovimentoDaAutomacao; `origem: 'carteira'`).
#
# Um card por seguro. O seguro fica travado do começo ao fim e é relido sob a trava: duas passadas da rotina ao mesmo
# tempo não criam dois cards (o índice único de `crm_card_id` é a segunda barreira). O card, o vínculo e o passo da
# história entram juntos ou não entram. O título não leva dado da pessoa: só a seguradora.
class Carteira::Renovacao::CriarCard
  ORIGEM = 'carteira'.freeze
  NASCEU = 'card_nasceu'.freeze

  def initialize(account, config)
    @account = account
    @config = config
    @locale = account.locale.presence || I18n.default_locale
    @fuso = Crm::Timezone::Resolver.new(account: account).name_or_default
  end

  # true quando o card nasceu; false quando o seguro já não entra (outra passada chegou antes, ou ele ganhou desfecho).
  def call(apolice)
    apolice.with_lock(requires_new: true) do
      next false unless Carteira::Renovacao::EntramHoje.entra?(apolice)

      apolice.update!(crm_card: criar(apolice))
      apolice.eventos.create!(tipo: NASCEU, quando: Time.current)
      true
    end
  end

  private

  def criar(apolice)
    Crm::Cards::Creator.new(account: @account, user: nil, params: do_card(apolice), automacao: { origem: ORIGEM, id: apolice.id }).perform
  end

  def do_card(apolice)
    { pipeline_id: @config.pipeline_id, stage_id: @config.stage_id, contact_id: apolice.contact_id,
      title: I18n.t('carteira.renovacao.card.titulo', seguradora: apolice.seguradora, locale: @locale),
      expected_close_at: apolice.fim_vigencia.in_time_zone(@fuso).end_of_day }
  end
end
