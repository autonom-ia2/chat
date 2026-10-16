# Monta uma conta de teste a partir de um modelo de fixtures/estrutura.json: caixa(s), funis com etapas, critérios e IA
# do funil, regra de Atribuição, quem cuida de cada funil, campos personalizados e flags. Uma conta nova por conversa:
# presença, intervalos e cotas de uma conversa não vazam para a outra.
#
# `outras_caixas` (ex.: e-mail) recebem a mesma configuração de CRM da caixa principal (mesmos funis, IA de assunto e
# quem cuida), como numa corretora que atende o mesmo cliente por WhatsApp e por e-mail.
class Stress::Mundo
  SENHA = 'Stress!Teste123'.freeze

  attr_reader :account, :funis, :etapas, :pessoas, :caixas

  def initialize(modelo:, nome:)
    @modelo = modelo
    @nome = nome
    @funis = {}
    @etapas = {}
    @pessoas = {}
    @caixas = {}
  end

  def montar
    @account = Account.create!(name: "Stress #{@nome}", locale: 'pt_BR')
    ligar_flags
    criar_pessoas
    criar_caixas
    criar_funis
    @caixas.each { |chave, inbox| ligar_caixa(inbox, configuracao_da_caixa(chave)) }
    @caixas.each_value { |inbox| criar_acessos(inbox) }
    criar_atributos
    self
  end

  def inbox
    @caixas.fetch('principal')
  end

  def etapa(funil, chave)
    @etapas.fetch([funil, chave]) { raise "etapa desconhecida #{funil}/#{chave}" }
  end

  def chave_da_etapa(stage)
    @etapas.key(stage)&.last
  end

  def chave_do_funil(pipeline)
    @funis.key(pipeline)
  end

  private

  def ligar_flags
    @account.enable_features!(*Array(@modelo['flags']))
  end

  def criar_pessoas
    Array(@modelo['atendentes']).each do |dados|
      user = User.create!(name: dados['nome'], email: "#{dados['chave']}.#{@account.id}@stress.invalid", password: SENHA,
                          confirmed_at: Time.current)
      AccountUser.create!(account: @account, user: user, role: dados['papel'] || 'agent')
      @pessoas[dados['chave']] = user
    end
  end

  def criar_caixas
    @caixas['principal'] = criar_caixa(@modelo.dig('caixa', 'nome'), 'api')
    Array(@modelo['outras_caixas']).each { |dados| @caixas[dados['chave']] = criar_caixa(dados['nome'], dados['tipo']) }
  end

  def criar_caixa(nome, tipo)
    canal = if tipo == 'email'
              Channel::Email.create!(account: @account, email: "contato.#{@account.id}.#{SecureRandom.hex(3)}@stress.invalid")
            else
              Channel::Api.create!(account: @account)
            end
    caixa = Inbox.create!(account: @account, channel: canal, name: nome)
    @pessoas.each_value { |user| InboxMember.create!(inbox: caixa, user: user) }
    caixa
  end

  def criar_funis
    Array(@modelo['funis']).each_with_index do |dados, posicao|
      pipeline = Crm::Pipeline.create!(account: @account, name: dados['nome'], description: dados['descricao'],
                                       when_to_use: dados['quando_usar'], counts_as_sale: dados.fetch('venda', true),
                                       position: posicao, metadata: { 'ai' => dados['ia'] || {} })
      @funis[dados['chave']] = pipeline
      criar_etapas(pipeline, dados)
    end
  end

  def criar_etapas(pipeline, dados)
    Array(dados['etapas']).each_with_index do |etapa, posicao|
      metadata = { 'ai_criteria' => etapa['criterio'].to_s }
      metadata['ai_handoff'] = etapa['atribuicao'] if etapa['atribuicao']
      stage = Crm::PipelineStage.create!(account: @account, pipeline: pipeline, name: etapa['nome'],
                                         description: etapa['descricao'], position: posicao,
                                         win_probability: etapa['chance'] || 0, is_won_stage: etapa['ganho'] == true,
                                         is_lost_stage: etapa['perdido'] == true, metadata: metadata)
      @etapas[[dados['chave'], etapa['chave']]] = stage
    end
  end

  def configuracao_da_caixa(chave)
    extra = Array(@modelo['outras_caixas']).find { |dados| dados['chave'] == chave } || {}
    @modelo['caixa'].merge(extra.slice('cria_card', 'ia_de_assunto'))
  end

  def ligar_caixa(caixa_inbox, caixa)
    padrao = @funis[caixa['funil_padrao']]
    Crm::InboxSetting.create!(account: @account, inbox: caixa_inbox, crm_enabled: true, auto_create_card: caixa['cria_card'] == true,
                              subject_ai_mode: caixa['ia_de_assunto'] || 'off', default_pipeline: padrao)
    Array(caixa['funis']).each do |chave|
      pipeline = @funis.fetch(chave)
      Crm::PipelineInbox.create!(account: @account, pipeline: pipeline, inbox: caixa_inbox, auto_create_card: caixa['cria_card'] == true,
                                 default_stage: pipeline.stages.order(:position).first)
    end
  end

  # Quem cuida de cada funil na caixa ("Quem cuida do quê?"): sem lista, a pessoa cuida de todos.
  def criar_acessos(caixa_inbox)
    Array(@modelo['atendentes']).each do |dados|
      funis = Array(dados['funis'])
      acesso = Crm::InboxAgentAccess.create!(account: @account, inbox: caixa_inbox, user: @pessoas[dados['chave']],
                                             all_pipelines: funis.empty?, triage: dados.fetch('triagem', true))
      funis.each { |chave| Crm::InboxAgentPipeline.create!(account: @account, access: acesso, pipeline: @funis.fetch(chave)) }
    end
  end

  def criar_atributos
    Array(@modelo['atributos']).each do |dados|
      CustomAttributeDefinition.create!(account: @account, attribute_display_name: dados['nome'], attribute_key: dados['chave'],
                                        attribute_display_type: dados['tipo'], attribute_model: dados['modelo'],
                                        attribute_values: dados['valores'] || [], attribute_description: dados['descricao'])
    end
  end
end
