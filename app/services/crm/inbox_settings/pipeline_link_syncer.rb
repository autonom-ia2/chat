# Configurar inbox passa a bastar (issue #499).
#
# Para um card nascer sozinho o CardSyncer exige DUAS coisas: a configuração da
# caixa (Crm::InboxSetting) e o vínculo funil↔caixa (Crm::PipelineInbox) com
# auto_create_card. Faltando o vínculo, o CardSyncer devolve vazio e não cria
# card nenhum, sem erro e sem aviso — era a terceira parada do fluxo, em Editar
# funil, e a mais esquecida nas implantações.
#
# Este serviço faz o vínculo sair junto do salvamento da caixa. O bloco "Inbox e
# automação" do Editar funil continua valendo para quem quer uma caixa
# alimentando mais de um funil: só deixou de ser obrigatório.
class Crm::InboxSettings::PipelineLinkSyncer
  def initialize(inbox_setting:, user: nil, pipeline_trocado: false)
    @setting = inbox_setting
    @user = user
    @pipeline_trocado = pipeline_trocado
  end

  def perform
    return desligar_todos unless ligado?

    vinculo = sincronizar_vinculo
    desligar_outros_funis if @pipeline_trocado
    vinculo
  end

  private

  def ligado?
    @setting.crm_enabled? && @setting.default_pipeline_id.present?
  end

  def sincronizar_vinculo
    vinculo = account.crm_pipeline_inboxes.find_or_initialize_by(
      pipeline_id: @setting.default_pipeline_id,
      inbox_id: @setting.inbox_id
    )
    vinculo.default_stage_id = @setting.default_stage_id
    vinculo.auto_create_card = @setting.auto_create_card?
    vinculo.created_by ||= @user
    vinculo.save!
    vinculo
  end

  # Só na troca de funil. Fora dela, mexer nos outros vínculos apagaria o ajuste
  # fino de quem ligou a mesma caixa em mais de um funil de propósito.
  def desligar_outros_funis
    desligar(vinculos_ligados.where.not(pipeline_id: @setting.default_pipeline_id))
  end

  # Caixa sem CRM não alimenta funil nenhum. O vínculo fica no lugar, com a
  # criação automática desligada: histórico preservado, comportamento parado.
  def desligar_todos
    desligar(vinculos_ligados)
    nil
  end

  # Um a um, e não em massa: são poucos vínculos por caixa, e assim as validações
  # e os callbacks do modelo continuam valendo.
  def desligar(escopo)
    escopo.each { |vinculo| vinculo.update!(auto_create_card: false) }
  end

  def vinculos_ligados
    account.crm_pipeline_inboxes.where(inbox_id: @setting.inbox_id, auto_create_card: true)
  end

  def account
    @setting.account
  end
end
