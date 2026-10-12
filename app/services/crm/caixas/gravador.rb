# Caixas no CRM (#1149): grava a caixa inteira de uma vez (R16) — o que chega, o que o sistema faz sozinho e quem
# cuida de quê.
#
# - Um funil: o card nasce nele, na etapa escolhida, assim que a conversa chega ('chegou') ou à mão ('off'). É o
#   comportamento de sempre (InboxSetting + vínculo com auto_create_card).
# - Vários funis: nenhum card nasce num funil fixo (R9). Quem cria é a IA de assunto ('auto' ou 'suggest') ou a
#   equipe ('off').
# - Nenhum funil: a caixa sai do CRM. Os vínculos ficam, com a criação desligada, como o PipelineLinkSyncer faz.
# - Pessoa que cuida de tudo (sem assunto, todos os funis, todas as conversas) fica sem linha de acesso: é o mesmo
#   que não ter configuração (R5). Administrador e usuário de integração nunca ganham linha.
class Crm::Caixas::Gravador
  class Invalida < StandardError
    attr_reader :code

    def initialize(code)
      @code = code
      super(code)
    end
  end

  MODOS_UM_FUNIL = %w[chegou off].freeze
  MODOS_VARIOS = %w[auto suggest off].freeze

  def initialize(account:, inbox:, user:, dados:)
    @account = account
    @inbox = inbox
    @user = user
    @dados = dados
  end

  def perform
    validar!
    ActiveRecord::Base.transaction do
      gravar_configuracao!
      gravar_vinculos!
      gravar_acessos!
    end
  end

  private

  def validar!
    erro = primeiro_erro
    raise Invalida, erro if erro
  end

  def primeiro_erro
    return 'crm.caixas.funil_invalido' unless (pipeline_ids - funis_da_conta.map(&:id)).empty?
    return 'crm.caixas.modo_invalido' unless modos_validos.include?(modo)
    return 'crm.caixas.etapa_invalida' if um_funil? && etapa.nil?
    return 'crm.caixas.pessoa_invalida' unless (pessoas.keys - agentes.keys).empty?

    'crm.caixas.sem_triagem' if falta_triagem?
  end

  def modos_validos
    return %w[off] if pipeline_ids.empty?

    um_funil? ? MODOS_UM_FUNIL : MODOS_VARIOS
  end

  # R7: com mais de um funil, alguém da caixa precisa ver as conversas ainda sem assunto.
  def falta_triagem?
    return false if pipeline_ids.size < 2 || agentes.empty?

    agentes.keys.none? { |user_id| triagem?(user_id) }
  end

  def gravar_configuracao!
    setting = @account.crm_inbox_settings.find_or_initialize_by(inbox: @inbox)
    setting.update!(
      crm_enabled: pipeline_ids.any?,
      default_pipeline_id: um_funil? ? pipeline_ids.first : nil,
      default_stage_id: etapa&.id,
      auto_create_card: um_funil? && modo == 'chegou',
      subject_ai_mode: um_funil? || pipeline_ids.empty? ? 'off' : modo,
      visibility_mode: :all_inbox_cards
    )
  end

  def gravar_vinculos!
    vinculos = @account.crm_pipeline_inboxes.where(inbox_id: @inbox.id)
    return vinculos.find_each { |vinculo| vinculo.update!(auto_create_card: false) } if pipeline_ids.empty?

    vinculos.where.not(pipeline_id: pipeline_ids).destroy_all
    pipeline_ids.each do |pipeline_id|
      vinculo = vinculos.find_or_initialize_by(pipeline_id: pipeline_id, account_id: @account.id)
      vinculo.assign_attributes(auto_create_card: um_funil? && modo == 'chegou', default_stage_id: um_funil? ? etapa.id : nil)
      vinculo.created_by ||= @user
      vinculo.save!
    end
  end

  def gravar_acessos!
    agentes.each_key do |user_id|
      next unless pessoas.key?(user_id)

      restrito?(user_id) ? gravar_acesso!(user_id) : apagar_acesso!(user_id)
    end
  end

  def gravar_acesso!(user_id)
    access = Crm::InboxAgentAccess.find_or_initialize_by(account_id: @account.id, inbox_id: @inbox.id, user_id: user_id)
    access.update!(all_pipelines: todos_os_funis?(user_id), triage: triagem?(user_id), only_own: so_as_suas?(user_id))
    desejados = todos_os_funis?(user_id) ? [] : funis_da_pessoa(user_id)
    access.agent_pipelines.where.not(pipeline_id: desejados).destroy_all
    (desejados - access.agent_pipelines.pluck(:pipeline_id)).each do |pipeline_id|
      access.agent_pipelines.create!(account_id: @account.id, pipeline_id: pipeline_id)
    end
  end

  def apagar_acesso!(user_id)
    Crm::InboxAgentAccess.find_by(account_id: @account.id, inbox_id: @inbox.id, user_id: user_id)&.destroy!
  end

  def restrito?(user_id)
    !(triagem?(user_id) && todos_os_funis?(user_id) && !so_as_suas?(user_id))
  end

  # Com um funil só não existe "sem assunto" separado: quem cuida do funil cuida também da conversa sem card.
  def triagem?(user_id)
    return funis_da_pessoa(user_id).any? if um_funil?

    ActiveModel::Type::Boolean.new.cast(pessoas.dig(user_id, 'triage')) || false
  end

  def todos_os_funis?(user_id)
    (pipeline_ids - funis_da_pessoa(user_id)).empty?
  end

  def funis_da_pessoa(user_id)
    Array(pessoas.dig(user_id, 'pipeline_ids')).map(&:to_i) & pipeline_ids
  end

  def so_as_suas?(user_id)
    ActiveModel::Type::Boolean.new.cast(pessoas.dig(user_id, 'only_own')) || false
  end

  def um_funil?
    pipeline_ids.size == 1
  end

  def modo
    @dados[:modo].to_s
  end

  def pipeline_ids
    @pipeline_ids ||= Array(@dados[:pipeline_ids]).map(&:to_i).uniq
  end

  def etapa
    return unless um_funil?

    @etapa ||= begin
      stages = funis_da_conta.find { |pipeline| pipeline.id == pipeline_ids.first }.stages.order(:position, :id)
      stages.find_by(id: @dados[:default_stage_id]) || stages.first
    end
  end

  def funis_da_conta
    @funis_da_conta ||= @account.crm_pipelines.active.to_a
  end

  # Quem a tela pode mudar: membro da caixa, nem administrador nem usuário de integração.
  def agentes
    @agentes ||= @account.account_users.where(user_id: @inbox.inbox_members.select(:user_id))
                         .reject { |account_user| account_user.administrator? || account_user.integration? }
                         .index_by(&:user_id)
  end

  def pessoas
    @pessoas ||= Array(@dados[:people]).index_by { |pessoa| pessoa['id'].to_i }
  end
end
