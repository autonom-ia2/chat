# A CORRETORA CONTRATA O AGENTE PRONTO (#3211): nasce um `sdr` com a marca do catálogo, em rascunho e parado ("Falta
# terminar" na tela) até o acesso à seguradora ficar `ok` e a caixa ser escolhida (o `InboxConnector` ativa). A
# instrução gravada é só o retrato do nascimento: a que vale é montada a cada turno (`Contratados::Instrucao`). As
# prontas do modelo (CEP e CPF) entram junto; a base oficial é semeada depois do commit, em segundo plano
# (`SemearBaseJob`), porque passa pela chamada paga de embedding. Uma conta pode contratar várias cópias (uma por
# corretora).
class Autonomia::Agents::Contratados::Contratar
  # A recusa leva o motivo (`indisponivel`, `nome_agente`, `nome_corretora`, `sobre_corretora` ou `marcador`) e o campo
  # da tela que a causou (R14), para a tela destacar o campo. `campo` é nil no `indisponivel` (nenhum campo resolve).
  class Recusado < StandardError
    attr_reader :motivo, :campo

    def initialize(motivo, campo: nil)
      @motivo = motivo
      @campo = campo
      super(motivo)
    end
  end

  # Campo da tela => tamanho mínimo e máximo, na ordem em que a tela os mostra (a primeira recusa é a do primeiro campo).
  CAMPOS = {
    'nome_agente' => 1..Autonomia::Agents::Contratados::Instrucao::MAX_NOME,
    'nome_corretora' => 1..Autonomia::Agents::Contratados::Instrucao::MAX_NOME,
    'sobre_corretora' => 0..Autonomia::Agents::Contratados::Instrucao::MAX_SOBRE
  }.freeze

  USAR_QUANDO = {
    'cep' => 'na proposta, para achar o endereço do titular pelo CEP',
    'cpf' => 'na proposta, para conferir cada CPF assim que chegar'
  }.freeze

  # As conferências do Contratar e da troca dos dados (`DadosDaCorretora`). -> os três valores limpos, nas chaves da
  # marca. Recusa o primeiro campo fora do tamanho ou com um marcador da instrução dentro (um nome com `$nomeAgente`
  # mudaria o texto que o modelo lê).
  def self.conferir!(account:, modelo:, nome_agente:, nome_corretora:, sobre_corretora:)
    raise Recusado, 'indisponivel' unless Autonomia::Agents::Contratados.disponivel?(account, modelo)

    valores = { 'nome_agente' => nome_agente, 'nome_corretora' => nome_corretora, 'sobre_corretora' => sobre_corretora }
              .transform_values { |valor| valor.to_s.strip }
    CAMPOS.each do |campo, tamanho|
      raise Recusado.new(campo, campo: campo) unless tamanho.cover?(valores[campo].length)
      raise Recusado.new('marcador', campo: campo) if Autonomia::Agents::Contratados::Instrucao.marcador_dentro?(valores[campo])
    end
    valores
  end

  def initialize(account:, user:, modelo:, nome_agente:, nome_corretora:, sobre_corretora:) # rubocop:disable Metrics/ParameterLists
    @account = account
    @user = user
    @chave = modelo.to_s
    @dados = { nome_agente: nome_agente, nome_corretora: nome_corretora, sobre_corretora: sobre_corretora }
  end

  def call
    valores = self.class.conferir!(account: @account, modelo: @chave, **@dados)
    agente = ActiveRecord::Base.transaction do
      novo = criar_agente!(valores)
      incluir_prontas!(novo)
      novo
    end
    Autonomia::Agents::Contratados::SemearBaseJob.perform_later(agente.id)
    agente
  end

  private

  def modelo
    Autonomia::Agents::Contratados::MODELOS.fetch(@chave)
  end

  def criar_agente!(valores)
    agente = Autonomia::Agents::Agent.new(
      account: @account, created_by: @user, name: valores['nome_agente'], agent_type: modelo[:agent_type],
      status: :draft, enabled: false, mode: :guided,
      config: { Autonomia::Agents::Contratados::MARCA => { 'modelo' => @chave }.merge(valores),
                'with_knowledge' => true }.merge(modelo[:conversa])
    )
    agente.instruction = Autonomia::Agents::Contratados::Instrucao.renderizar(agente)
    agente.save!(context: %i[create ativacao])
    agente
  end

  # A pronta recusada aqui só acontece com a fonte desligada na conta entre a conferência e o "Incluir": a contratação
  # volta inteira e a tela recebe `indisponivel`. O motivo da recusa vai para o log, que não leva dado da corretora.
  def incluir_prontas!(agente)
    modelo[:prontas].each do |fonte|
      Autonomia::FerramentasProntas::Incluir.new(account: @account, agent: agente, fonte: fonte, user: @user,
                                                 pelo_contratar: true, usar_quando: USAR_QUANDO.fetch(fonte)).call
    end
  rescue Autonomia::FerramentasProntas::Incluir::Recusado => e
    Rails.logger.warn("[autonomia][contratados] pronta recusada no contratar conta=#{@account.id} motivo=#{e.motivo}")
    raise Recusado, 'indisponivel'
  end
end
