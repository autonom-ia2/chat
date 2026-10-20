# Funil ainda não salvo (#1384): a tela de criar funil mostra o critério padrão das etapas
# e oferece "Criar/Melhorar com IA" antes de o funil existir. O texto padrão continua
# morando só em Crm::Ai::DefaultStageCriteria — a tela pede, não copia.
class Api::V1::Accounts::Crm::StageCriteriaController < Api::V1::Accounts::Crm::BaseController
  include DeferInteractiveAi

  before_action :ensure_crm_ai_enabled
  before_action :authorize_draft_pipeline

  def defaults
    names = Array(params[:names]).first(Crm::Ai::StageCriteriaImprover::MAX_STAGES).map(&:to_s)
    # #1498: funil de Atender tem frases próprias para nomes que também existem em venda ("Em atendimento").
    atender = ActiveModel::Type::Boolean.new.cast(params[:atender]) || false
    # #1548: modelo do funil novo e a posição de cada etapa nele (0 = etapa que a pessoa criou), na ordem dos nomes.
    positions = Array(params[:positions])
    render json: {
      payload: names.each_with_index.map do |name, index|
        criteria = Crm::Ai::DefaultStageCriteria.criteria_for(name, atender: atender, template: params[:template], position: positions[index])
        { name: name, criteria: criteria.to_s }
      end
    }
  end

  def improve
    raw_input = params.slice(:stages, :stage_index).to_unsafe_h
    return render_unprocessable('invalid_stage_criteria') unless Crm::Ai::StageCriteriaImprover.valid_input?(raw_input)

    input = params.permit(:stage_index, :pipeline_name, stages: [:name, :description]).to_h
    defer_interactive_ai('stage_criteria_draft', {
                           pipeline_name: input['pipeline_name'].to_s.strip.first(Crm::Ai::StageCriteriaImprover::MAX_NAME_LENGTH),
                           stages: input.fetch('stages'), stage_index: input.fetch('stage_index'), language: I18n.locale.to_s,
                           funil: funil_do_formulario
                         })
  end

  private

  # #1920: o tipo e o "quando usar" que estão no formulário, para a IA que escreve a frase.
  def funil_do_formulario
    Crm::Ai::ContextoDoFunil.do_formulario(params.permit(funil: %i[counts_as_sale when_to_use])[:funil])
  end

  # Quem pode criar funil e usar IA de funil — o mesmo par que o funil salvo exige.
  def authorize_draft_pipeline
    draft = Current.account.crm_pipelines.new
    authorize draft, :create?
    authorize draft, :manage_ai?
  end
end
