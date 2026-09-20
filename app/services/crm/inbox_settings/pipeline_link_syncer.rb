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

  # Dois salvamentos simultâneos da mesma caixa acham o vínculo inexistente ao
  # mesmo tempo e o segundo esbarra no índice único (conta, funil, caixa). Nesse
  # caso o registro já existe: basta reabrir e atualizar.
  #
  # O insert vai num savepoint porque o controller já abriu transação: no
  # Postgres, o erro derruba a transação inteira e o resgate seguinte falharia
  # com "current transaction is aborted".
  def sincronizar_vinculo
    existente = vinculo_existente
    return gravar_vinculo(existente) if existente.present?

    begin
      ActiveRecord::Base.transaction(requires_new: true) { gravar_vinculo(novo_vinculo) }
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => e
      # A corrida aparece de dois jeitos: pela validação de unicidade do modelo
      # ou pelo índice do banco, conforme o momento em que o outro salvamento
      # gravou. Qualquer outra falha (etapa de outro funil, por exemplo) segue
      # subindo — só tratamos o caso em que o vínculo passou a existir.
      concorrente = vinculo_existente
      raise e if concorrente.blank?

      gravar_vinculo(concorrente)
    end
  end

  def gravar_vinculo(vinculo)
    vinculo.default_stage_id = @setting.default_stage_id
    vinculo.auto_create_card = @setting.auto_create_card?
    vinculo.created_by ||= @user
    vinculo.save!
    vinculo
  end

  def novo_vinculo
    account.crm_pipeline_inboxes.new(
      pipeline_id: @setting.default_pipeline_id,
      inbox_id: @setting.inbox_id
    )
  end

  def vinculo_existente
    account.crm_pipeline_inboxes.find_by(
      pipeline_id: @setting.default_pipeline_id,
      inbox_id: @setting.inbox_id
    )
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
