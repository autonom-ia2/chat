# O Guia que faz, com confirmação (issue #536).
#
# O Guia NUNCA executa direto. Este catálogo tem duas metades por ação:
# `descrever`, que devolve em português o que vai acontecer com os valores
# exatos, e `executar`, que só roda depois de a pessoa confirmar na tela.
#
# Três regras que este arquivo não negocia:
#
# 1. A superfície é fechada. Só existe o que está em CATALOGO; pedido fora da
#    lista é recusado, não interpretado.
# 2. Autorização é herdada, não reescrita: cada ação passa pela policy do
#    próprio domínio, com o contexto de quem pediu. Agente comum não executa
#    nada desta fatia, mesmo pedindo de outro jeito.
# 3. Nada que fale com cliente, gaste dinheiro ou mexa em acesso: sem campanha,
#    sem faturamento, sem usuário e sem credencial de integração.
class Autonomia::Guide::Acoes
  class Recusada < StandardError; end

  CATALOGO = %w[criar_funil ligar_caixa_ao_funil criar_etiqueta].freeze

  Resultado = Struct.new(:ok, :mensagem, :registro, keyword_init: true)

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  # O texto que a pessoa lê ANTES de confirmar. Sem isso não há confirmação
  # informada — e confirmação no escuro não é confirmação.
  def descrever(acao, params)
    garantir_permitida!(acao)
    dados = normalizar(acao, params)

    case acao.to_s
    when 'criar_funil'
      "Criar o funil \"#{dados[:nome]}\" com as etapas #{dados[:etapas].join(', ')}."
    when 'ligar_caixa_ao_funil'
      descrever_vinculo(dados)
    when 'criar_etiqueta'
      "Criar a etiqueta \"#{dados[:titulo]}\"."
    end
  end

  def executar(acao, params)
    garantir_permitida!(acao)
    dados = normalizar(acao, params)

    ActiveRecord::Base.transaction { send("executar_#{acao}", dados) }
  rescue ActiveRecord::RecordInvalid => e
    Resultado.new(ok: false, mensagem: e.record.errors.full_messages.to_sentence)
  end

  private

  def garantir_permitida!(acao)
    raise Recusada, 'Esta ação não existe no Guia.' unless CATALOGO.include?(acao.to_s)
    raise Recusada, 'Só o administrador da conta faz isso.' unless administrador?
  end

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  # Nome escrito por quem pede vira nome de funil, de etapa e de etiqueta. Mesma
  # higiene das leituras: sem colchete, sem quebra de linha, com tamanho limitado.
  def limpo(valor, tamanho = 60)
    valor.to_s.gsub(/[\[\]\r\n]/, ' ').gsub(/[[:cntrl:]]/, ' ').squeeze(' ').strip[0, tamanho].to_s
  end

  ETAPAS_PADRAO = ['Novo Lead', 'Em contato', 'Proposta', 'Fechado'].freeze

  def normalizar(acao, params)
    p = params.to_h.symbolize_keys

    case acao.to_s
    when 'criar_funil'
      etapas = Array(p[:etapas]).map { |e| limpo(e, 40) }.reject(&:blank?)
      { nome: limpo(p[:nome]), etapas: etapas.presence || ETAPAS_PADRAO }
    when 'ligar_caixa_ao_funil'
      { inbox_id: p[:inbox_id], pipeline_id: p[:pipeline_id], auto_create_card: p[:auto_create_card] != false }
    when 'criar_etiqueta'
      { titulo: limpo(p[:titulo], 40) }
    end
  end

  def descrever_vinculo(dados)
    inbox = @account.inboxes.find_by(id: dados[:inbox_id])
    pipeline = @account.crm_pipelines.find_by(id: dados[:pipeline_id])
    raise Recusada, 'Não achei essa caixa ou esse funil nesta conta.' if inbox.nil? || pipeline.nil?

    criacao = dados[:auto_create_card] ? 'e os cards passam a nascer sozinhos' : 'sem criar cards automaticamente'
    "Ligar a caixa \"#{limpo(inbox.name)}\" ao funil \"#{limpo(pipeline.name)}\", #{criacao}."
  end

  def autorizar!(registro, permissao)
    contexto = { user: @user, account: @account, account_user: @account_user }
    raise Recusada, 'Você não tem permissão para isso.' unless Pundit.policy!(contexto, registro).public_send(permissao)
  end

  def executar_criar_funil(dados)
    raise Recusada, 'O funil precisa de um nome.' if dados[:nome].blank?

    pipeline = @account.crm_pipelines.new(name: dados[:nome], created_by: @user, status: :active)
    autorizar!(pipeline, :create?)
    pipeline.save!
    dados[:etapas].each_with_index do |etapa, posicao|
      @account.crm_pipeline_stages.create!(pipeline: pipeline, name: etapa, position: posicao)
    end

    Resultado.new(ok: true, mensagem: "Funil \"#{pipeline.name}\" criado com #{dados[:etapas].size} etapas.",
                  registro: pipeline)
  end

  def executar_ligar_caixa_ao_funil(dados)
    inbox = @account.inboxes.find_by(id: dados[:inbox_id])
    pipeline = @account.crm_pipelines.find_by(id: dados[:pipeline_id])
    raise Recusada, 'Não achei essa caixa ou esse funil nesta conta.' if inbox.nil? || pipeline.nil?

    vinculo = @account.crm_pipeline_inboxes.find_or_initialize_by(pipeline_id: pipeline.id, inbox_id: inbox.id)
    autorizar!(pipeline, :update?)
    vinculo.auto_create_card = dados[:auto_create_card]
    vinculo.created_by ||= @user
    vinculo.save!

    Resultado.new(ok: true, mensagem: "A caixa \"#{inbox.name}\" agora alimenta o funil \"#{pipeline.name}\".",
                  registro: vinculo)
  end

  def executar_criar_etiqueta(dados)
    raise Recusada, 'A etiqueta precisa de um nome.' if dados[:titulo].blank?

    label = @account.labels.new(title: dados[:titulo])
    autorizar!(label, :create?)
    label.save!

    Resultado.new(ok: true, mensagem: "Etiqueta \"#{label.title}\" criada.", registro: label)
  end
end
