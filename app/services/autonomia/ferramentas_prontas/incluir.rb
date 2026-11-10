# O "INCLUIR" DA VITRINE (#2858, F0: só o serviço; a tela é a F2). Ensina uma fonte do catálogo a um agente da conta:
#   - cria (ou reaproveita) a chave interna da conta naquela fonte (`Acesso`), com o limite e o corte;
#   - cria (ou religa) a ferramenta pronta no agente, com a frase "Use quando…" da conta.
# Incluir de novo não duplica nada: atualiza a frase e religa. Quem pode incluir (administrador ou a chave
# "Ferramentas dos agentes") é conferido por quem chama, na tela da F2.
#
# Recusa (`Recusado#motivo`): flag desligada, agente de outra conta, a Lia, fonte fora do catálogo, ou o nome da função
# já usado por uma ferramenta cadastrada à mão no mesmo agente.
class Autonomia::FerramentasProntas::Incluir
  MAX_USAR_QUANDO = 500

  class Recusado < StandardError
    def motivo
      message
    end
  end

  Resultado = Data.define(:ferramenta, :acesso)

  def initialize(account:, agent:, fonte:, usar_quando: nil, user: nil)
    @account = account
    @agent = agent
    @fonte = Autonomia::FerramentasProntas::Catalogo.buscar(fonte)
    @usar_quando = usar_quando.to_s.squish.first(MAX_USAR_QUANDO).presence
    @user = user
  end

  def call
    conferir!
    ActiveRecord::Base.transaction do
      acesso = Autonomia::FerramentasProntas::Acesso.create_or_find_by!(account_id: @account.id, fonte: @fonte.chave) do |novo|
        novo.incluida_por_id = @user&.id
      end
      Resultado.new(ferramenta: ferramenta!, acesso: acesso)
    end
  end

  private

  def conferir!
    raise Recusado, 'desligada' unless Autonomia::FerramentasProntas.ligada?(@account)
    raise Recusado, 'agente_de_outra_conta' unless @agent.account_id == @account.id
    raise Recusado, 'agente_de_cotacao' if @agent.agent_type == Autonomia::FerramentasProntas::AGENTE_DE_COTACAO
    raise Recusado, 'fonte_desconhecida' if @fonte.nil?
  end

  def ferramenta!
    tool = @agent.tools.find_or_initialize_by(slug: @fonte.slug)
    raise Recusado, 'nome_em_uso' if tool.persisted? && tool.fonte_pronta != @fonte.chave

    tool.assign_attributes(atributos)
    tool.save!
    tool
  end

  def atributos
    {
      account: @account, name: @fonte.nome, fonte_pronta: @fonte.chave, enabled: true,
      description: @usar_quando, http_method: 'GET', endpoint_url: '', timeout_seconds: @fonte.prazo_maximo + 1,
      headers_config: [], param_schema: [], request_body_template: nil, response_mapping: {}
    }
  end
end
