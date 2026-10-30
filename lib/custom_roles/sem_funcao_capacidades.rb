# O que o agente sem função consegue fazer, por capacidade (#2308, épico #1784). A tela Funções da equipe lê o JSON
# gerado daqui (`bundle exec rails autonomia:funcoes:sem_funcao`); o `:check` e o spec seguram o versionado em dia.
#
# Nada é escrito à mão: cada resposta pergunta à policy (ou à regra) de verdade, com um agente sem função personalizada
# feito em memória, sem banco. O que vale igual com e sem função (estar na caixa, ver o card, participar da coluna) entra
# como premissa, escrita no JSON; só a parte que muda com a função é perguntada. Resposta que muda com uma flag da conta
# (FLAGS) sai como `depende_da_flag`, com os dois valores. Cada fonte é conferida contra o código ao gerar: método que
# sumiu ou mudou de dono quebra a geração em vez de deixar o arquivo mentindo.
module CustomRoles::SemFuncaoCapacidades
  ARQUIVO = Rails.root.join('app/javascript/dashboard/routes/dashboard/settings/funcoesDaEquipe/semFuncaoCapacidades.json')
  COMANDO = 'bundle exec rails autonomia:funcoes:sem_funcao'.freeze
  # As flags da conta que podem mudar uma resposta: cada capacidade é perguntada com cada uma desligada e ligada.
  FLAGS = %w[crm_numeros_lentes].freeze

  # As premissas moram em ConversaAlcancada e CardAlcancado (pasta ao lado).
  Contexto = Struct.new(:account_user, :account) do
    def pode?(policy, record, *acoes)
      instancia = policy.new({ user: account_user.user, account: account, account_user: account_user }, record)
      acoes.all? { |acao| instancia.public_send(acao) }
    end

    def conversa_de_colega
      Conversation.new(assignee_id: account_user.user.id + 1)
    end
  end

  CAPACIDADES = [
    { id: 'conversas_dos_colegas', chaves: %w[conversation_manage], premissas: %w[na_caixa],
      fontes: %w[ConversationPolicy#agent_can_view_conversation? Crm::Access::ConversationScope#allows?
                 Enterprise::ConversationPolicy#show? Enterprise::ConversationPolicy#view?],
      pergunta: ->(c) { c.pode?(ConversaAlcancada, c.conversa_de_colega, :view?, :show?) } },
    { id: 'contatos', chaves: %w[contact_view contact_manage], premissas: [],
      fontes: %w[Relationships::RecordPermissions#relationship_record_read? Relationships::RecordPermissions#relationship_record_write?],
      pergunta: ->(c) { c.pode?(ContactPolicy, Contact.new, :index?, :update?) } },
    { id: 'respostas_prontas', chaves: %w[canned_response_manage], premissas: [],
      fontes: %w[CannedResponsePolicy#manage?],
      pergunta: ->(c) { c.pode?(CannedResponsePolicy, CannedResponse.new, :create?, :update?, :destroy?) } },
    { id: 'apagar_mensagens', chaves: %w[conversation_message_delete], premissas: %w[na_caixa],
      fontes: %w[Enterprise::ConversationPolicy#delete_message?],
      pergunta: ->(c) { c.pode?(ConversaAlcancada, c.conversa_de_colega, :delete_message?) } },
    { id: 'vendas_das_colunas', chaves: %w[crm_manage_cards crm_move_cards], premissas: %w[ve_o_card participa_da_coluna],
      fontes: %w[CrmPermissions#crm_permission? Enterprise::Crm::CardPolicy#update? Enterprise::Crm::CardPolicy#move?
                 Crm::CardPolicy#funnel_member?],
      pergunta: ->(c) { c.pode?(CardAlcancado, Crm::Card.new, :create?, :update?, :move?) } },
    { id: 'arquivar_vendas', chaves: %w[crm_delete_cards], premissas: %w[ve_o_card participa_da_coluna],
      fontes: %w[Enterprise::Crm::CardPolicy#destroy? CrmPermissions::PLAIN_AGENT_DENIED_KEYS],
      pergunta: ->(c) { c.pode?(CardAlcancado, Crm::Card.new, :destroy?) } },
    { id: 'relatorios_das_vendas', chaves: %w[crm_view_reports], premissas: [],
      fontes: %w[Enterprise::Crm::ReportPolicy#view? Crm::Config.numeros_lentes_enabled?],
      pergunta: ->(c) { c.pode?(Crm::ReportPolicy, %i[crm report], :view?) } },
    { id: 'procurar_clientes_novos', chaves: %w[prospecting_view prospecting_manage], premissas: [],
      fontes: %w[Api::BaseController#check_module_permission! Enterprise::AccountUser#permission_granted?],
      pergunta: ->(c) { c.account_user.permission_granted?('prospecting_view') } },
    { id: 'planilha_de_clientes', chaves: %w[contact_export crm_export], premissas: [],
      fontes: %w[Enterprise::ContactPolicy#export? Enterprise::Crm::CardPolicy#export? CrmPermissions::PLAIN_AGENT_DENIED_KEYS],
      pergunta: ->(c) { c.pode?(ContactPolicy, Contact.new, :export?) || c.pode?(CardAlcancado, Crm::Card.new, :export?) } },
    { id: 'valores_das_vendas', chaves: %w[sales_value_view], premissas: [],
      fontes: %w[Crm::ValorDeVenda.ve?],
      pergunta: ->(c) { Crm::ValorDeVenda.ve?(c.account_user) } },
    # As chaves que o sem função nunca recebe (CrmPermissions::PLAIN_AGENT_DENIED_KEYS) e as metas, que só a função dá.
    { id: 'montar_colunas', chaves: %w[crm_manage_pipelines], premissas: [],
      fontes: %w[Enterprise::Crm::PipelinePolicy#create? Enterprise::Crm::PipelinePolicy#update? CrmPermissions::PLAIN_AGENT_DENIED_KEYS],
      pergunta: ->(c) { c.pode?(Crm::PipelinePolicy, Crm::Pipeline.new, :create?, :update?) } },
    { id: 'ia_das_vendas', chaves: %w[crm_manage_ai], premissas: %w[ve_o_card participa_da_coluna],
      fontes: %w[Enterprise::Crm::CardPolicy#evaluate_ai? Enterprise::Crm::CardPolicy#summarize?
                 CrmPermissions::PLAIN_AGENT_DENIED_KEYS],
      pergunta: ->(c) { c.pode?(CardAlcancado, Crm::Card.new, :evaluate_ai?, :summarize?) } },
    # crm_admin liga todas as chaves crm_* da função (CrmPermissions#crm_permission?); só dele são as caixas do CRM
    # (quem vê o quê) e os calendários de SLA.
    { id: 'cuidar_de_tudo_nas_vendas', chaves: %w[crm_admin], premissas: [],
      fontes: %w[CrmPermissions#crm_permission? Enterprise::Crm::InboxAgentAccessPolicy#update?
                 Enterprise::Crm::ServiceSchedulePolicy#create? CrmPermissions::PLAIN_AGENT_DENIED_KEYS],
      pergunta: lambda { |c|
        c.pode?(Crm::InboxAgentAccessPolicy, %i[crm inbox_agent_access], :update?) &&
          c.pode?(Crm::ServiceSchedulePolicy, Crm::ServiceSchedule.new, :create?)
      } },
    { id: 'metas_do_mes', chaves: %w[crm_metas_manage], premissas: [],
      fontes: %w[Enterprise::Crm::MetasPolicy#manage?],
      pergunta: ->(c) { c.pode?(Crm::MetasPolicy, :metas, :manage?) } }
  ].freeze

  # Sem chave só deles: seguem do "sem função"; a chave que a função usa (quando há) abre mais que isso.
  EXTRAS = [
    # Quem lê: Crm::BookingV2::HostEligibility (eligible?/eligible_user_ids); a tela não mostra extra sem chave.
    { id: 'responsavel_de_agendamento', chaves: [], premissas: [],
      fontes: %w[Crm::BookingV2::HostEligibility.sees_cards?],
      pergunta: ->(c) { Crm::BookingV2::HostEligibility.send(:sees_cards?, c.account_user) } },
    # Com função, vê a origem do anúncio só com meta_ads_view; segue extra porque a chave também abre a página de
    # Anúncios, que o sem função não tem.
    { id: 'anuncio_de_origem', chaves: %w[meta_ads_view], premissas: [],
      fontes: %w[Crm::AnuncioDeOrigem.ve?],
      pergunta: ->(c) { Crm::AnuncioDeOrigem.ve?(c.account_user) } }
  ].freeze

  module_function

  # custom_role: nil é o agente sem função; o spec passa uma função para provar que as respostas mudam com ela.
  def gerar(custom_role: nil)
    { gerado_por: COMANDO,
      capacidades: CAPACIDADES.map { |capacidade| item(capacidade, custom_role) },
      extras: EXTRAS.map { |capacidade| item(capacidade, custom_role) } }
  end

  # As chaves que o "Sem função" tem nesta conta, com as flags dela (#2317): deixar alguém sem função entrega essas chaves,
  # e quem não é administrador precisa alcançá-las (CustomRoles::GrantGuard#no_role!). Os extras ficam de fora, como em
  # semFuncao.js: a chave de um extra abre mais do que o sem função tem (meta_ads_view abre a página de Anúncios).
  # A resposta é por capacidade, não por chave: uma pergunta com OU (planilha_de_clientes: contatos ou vendas) daria as
  # duas chaves se passasse. Hoje ela não passa com a flag nem sem ela, e o spec "não pode" segura isso; se mudar,
  # a capacidade precisa ser dividida por chave antes, no contrato, no JSON e na tela.
  def chaves(account)
    ligadas = FLAGS.select { |flag| account.feature_enabled?(flag) }
    CAPACIDADES.select { |capacidade| capacidade[:pergunta].call(contexto(ligadas, nil)) }
               .flat_map { |capacidade| capacidade[:chaves] }
  end

  def json
    "#{JSON.pretty_generate(gerar)}\n"
  end

  def escrever!
    FileUtils.mkdir_p(ARQUIVO.dirname)
    File.write(ARQUIVO, json)
  end

  def em_dia?
    File.exist?(ARQUIVO) && File.read(ARQUIVO) == json
  end

  def item(capacidade, custom_role)
    capacidade.except(:pergunta, :fontes)
              .merge(resposta(capacidade[:pergunta], custom_role))
              .merge(fontes: capacidade[:fontes].map { |fonte| { regra: fonte, arquivo: arquivo_da(fonte) } })
  end

  def resposta(pergunta, custom_role)
    desligada = pergunta.call(contexto([], custom_role))
    flag = FLAGS.find { |nome| pergunta.call(contexto([nome], custom_role)) != desligada }
    return { pode: desligada } if flag.nil?

    { depende_da_flag: { flag: flag, desligada: desligada, ligada: !desligada } }
  end

  def contexto(flags, custom_role)
    account = Account.new.tap { |conta| conta.enable_features(*flags) }
    Contexto.new(AccountUser.new(account: account, user: User.new(id: 1), role: :agent, custom_role: custom_role), account)
  end

  # 'Classe#metodo', 'Classe.metodo' ou 'Modulo::CONSTANTE' -> o arquivo, relativo ao projeto. O método precisa ser do
  # próprio dono citado: herdado ou sobrescrito por outro módulo não vale como fonte.
  def arquivo_da(fonte)
    caminho = if fonte.include?('#')
                fonte_de_metodo(*fonte.split('#'), :instance_method)
              elsif fonte.include?('.')
                fonte_de_metodo(*fonte.split('.'), :method)
              else
                Object.const_source_location(fonte).first
              end
    Pathname(caminho).relative_path_from(Rails.root).to_s
  end

  def fonte_de_metodo(dono, nome, leitura)
    constante = dono.constantize
    metodo = constante.public_send(leitura, nome)
    dono_esperado = leitura == :method ? constante.singleton_class : constante
    raise ArgumentError, "#{dono} não tem #{nome} próprio (é de #{metodo.owner})" unless metodo.owner == dono_esperado

    metodo.source_location.first
  end
end
