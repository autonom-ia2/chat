# "Criar cards" da Lista nova de Relacionamentos (#2894): um card aberto por pessoa marcada, no funil e na etapa
# escolhidos. Quem já tem card aberto naquele funil fica de fora (card fechado ou arquivado não impede).
#
# O card nasce pelo mesmo Crm::Cards::Creator do quadro, com a pessoa de dono e a etapa anotada como escolhida, e o
# quadro é avisado, como no envio em lote da Prospecção (Autonomia::Prospecting::CrmCardBatch). Funil que quem pede não
# enxerga (acesso por funil, #1148), arquivado ou de outra conta é um funil que não existe.
class Relacionamentos::CriarCards < Relacionamentos::AcaoEmGrupo
  JA_TEM_CARD = 'ja_tem_card'.freeze

  def initialize(funil_id:, etapa_id:, **)
    super(**)
    @funil_id = funil_id
    @etapa_id = etapa_id
  end

  private

  def contagem
    :criados
  end

  def preparar
    recusar('o CRM está desligado') unless Crm::Config.enabled?

    funis = Crm::Access::VisiblePipelines.new(user: @user, account: @account).apply(@account.crm_pipelines).active
    @funil = funis.find_by(id: @funil_id) || recusar('funil desconhecido')
    @etapa = @account.crm_pipeline_stages.find_by(id: @etapa_id, pipeline_id: @funil.id) || recusar('etapa não é deste funil')
  end

  # A pessoa fica travada enquanto se confere e se cria: dois pedidos ao mesmo tempo não criam dois cards para ela.
  def fazer(pessoa_id)
    card = ActiveRecord::Base.transaction do
      pessoa = @account.contacts.lock.find(pessoa_id)
      criar_card(pessoa) unless tem_card_aberto?(pessoa)
    end
    return JA_TEM_CARD unless card

    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_CREATED)
    nil
  end

  def tem_card_aberto?(pessoa)
    @account.crm_cards.exists?(contact_id: pessoa.id, pipeline_id: @funil.id, status: :open)
  end

  def criar_card(pessoa)
    params = { pipeline_id: @funil.id, stage_id: @etapa.id, contact_id: pessoa.id, title: titulo(pessoa) }
    Crm::Cards::Creator.new(account: @account, user: @user, params: params, etapa_escolhida: true).perform
  end

  def titulo(pessoa)
    pessoa.name.presence || pessoa.phone_number.presence || pessoa.email.presence
  end
end
