# Confere o login do corretor na Universal pelo Setup e grava o resultado no acesso do agente contratado (#3211).
# Nunca levanta o erro do cliente: o resultado da conferência é o próprio estado gravado.
class Autonomia::Agents::Contratados::ConferirAcesso
  Codigos = Autonomia::Seguradoras::Universal::Codigos

  # Nome do campo no Setup da Universal => a nossa chave em `capacidades`. Os nomes da esquerda são os do levantamento
  # de fatos (o resumo da coleção Postman não traz o Setup); a Tarefa 0b os confere na resposta real.
  CAPACIDADES = { 'soCotacao' => 'so_cotacao', 'emiteFaturado' => 'emite_faturado',
                  'emiteBoleto' => 'emite_boleto', 'tarifaAcordo' => 'tarifa_acordo' }.freeze

  # Erro do cliente => estado do acesso. `pedido_invalido` no Setup não é recusa de acesso: o login não foi julgado.
  ESTADO_POR_CODIGO = { Codigos::ACESSO_RECUSADO => 'recusado' }.freeze
  ESTADO_PADRAO = 'nao_conferido'.freeze

  def initialize(agent:, login:, senha:)
    @agent = agent
    @login = login
    @senha = senha
  end

  def call
    acesso = Autonomia::Agents::AcessoDaSeguradora.find_or_initialize_by(autonomia_agent_id: @agent.id)
    acesso.account_id = @agent.account_id
    acesso.login = @login
    acesso.senha = @senha
    acesso.assign_attributes(resultado)
    acesso.save!
    acesso
  end

  private

  def resultado
    setup = Autonomia::Seguradoras::Universal::Cliente.new(login: @login, senha: @senha).setup
    { estado: 'ok', motivo: nil, conferido_em: Time.current, capacidades: capacidades_de(setup) }
  rescue Autonomia::Seguradoras::Universal::Cliente::Erro => e
    { estado: ESTADO_POR_CODIGO.fetch(e.codigo, ESTADO_PADRAO), motivo: e.codigo, conferido_em: Time.current, capacidades: {} }
  end

  def capacidades_de(setup)
    campos = setup.is_a?(Hash) ? setup : {}
    CAPACIDADES.to_h { |deles, nossa| [nossa, campos[deles] == true] }
  end
end
