# #3211 — o login do corretor na seguradora do agente contratado (`Autonomia::Agents::AcessoDaSeguradora`).
#
# GET  .../agents/:agent_id/acesso_da_seguradora                   -> o `payload_publico`, ou { estado: 'nao_conferido' }
#                                                                     enquanto ninguém gravou o login.
# POST .../agents/:agent_id/acesso_da_seguradora { login, senha }   -> confere na hora pelo Setup da seguradora
#                                                                     (`Contratados::ConferirAcesso`) e devolve o
#                                                                     `payload_publico` (200 também com o login recusado:
#                                                                     o resultado é o estado gravado).
# A resposta nunca traz a senha nem o login inteiro, só a dica (R5); os dois saem filtrados do log do Rails e do Sentry
# (`filter_parameter_logging.rb`, `SentryHttpAuthScrubber`), e o Guia não grava o login (só na tela,
# `AcessoDaSeguradora::SO_NA_TELA_DO_GUIA`). A conferência cabe no prazo da requisição (`Universal::Cliente::LEITURA`):
# seguradora sem resposta vira `nao_conferido`/`indisponivel`, nunca 5xx. Agente de outra conta, de sistema ou que não é contratado:
# 404. Ler pede `autonomia_view`. Gravar é credencial de integração, que não se delega por função (CLAUDE.md, funções
# personalizadas): só o administrador, como as conexões e os tokens.
class Api::V1::Accounts::Autonomia::Agents::AcessoDaSeguradoraController < Api::V1::Accounts::Autonomia::BaseController
  include ::Autonomia::DadosDoContratado

  CREDENCIAIS = %i[login senha].freeze

  before_action :buscar_contratado
  before_action :somente_administrador, only: :create

  def show
    render json: @agent.acesso_da_seguradora&.payload_publico || { estado: ::Autonomia::Agents::Contratados::ConferirAcesso::ESTADO_PADRAO }
  end

  def create
    recusar_modelo_indisponivel!
    login, senha = credenciais.values_at(:login, :senha)
    return render_acesso_incompleto(login.blank? ? 'login' : 'senha') if login.blank? || senha.blank?

    acesso = ::Autonomia::Agents::Contratados::ConferirAcesso.new(agent: @agent, login: login, senha: senha).call
    render json: acesso.payload_publico
  end

  private

  def buscar_contratado
    @agent = agents_scope.find(params[:agent_id])
    raise ActiveRecord::RecordNotFound unless @agent.contratado?
  end

  # A flag do modelo desligada (ou sem o cofre): nada é conferido nem gravado, e a seguradora não é chamada.
  def recusar_modelo_indisponivel!
    modelo = ::Autonomia::Agents::Contratados.marca(@agent)['modelo']
    return if ::Autonomia::Agents::Contratados.disponivel?(Current.account, modelo)

    raise ::Autonomia::Agents::Contratados::Contratar::Recusado, 'indisponivel'
  end

  def somente_administrador
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  # O login sem os espaços das pontas; a senha como foi digitada (o espaço pode ser parte dela).
  def credenciais
    permitidas = params.permit(*CREDENCIAIS)
    { login: permitidas[:login].to_s.strip, senha: permitidas[:senha].to_s }
  end

  def render_acesso_incompleto(campo)
    render json: { error: I18n.t('autonomia.contratados.acesso_incompleto'), code: 'acesso_incompleto', campo: campo },
           status: :unprocessable_entity
  end
end
