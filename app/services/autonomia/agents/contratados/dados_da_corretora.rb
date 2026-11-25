# A CORRETORA TROCA OS SEUS DADOS NO AGENTE CONTRATADO (#3211): o nome do agente e o nome e a apresentação da
# corretora, com as mesmas conferências do `Contratar`. O modelo da marca não muda, e a base oficial não é semeada de
# novo (ela não depende desses dados). A instrução do turno seguinte já sai com os dados novos (`Contratados::Instrucao`).
class Autonomia::Agents::Contratados::DadosDaCorretora
  Recusado = Autonomia::Agents::Contratados::Contratar::Recusado

  def initialize(agent:, nome_agente:, nome_corretora:, sobre_corretora:)
    @agent = agent
    @dados = { nome_agente: nome_agente, nome_corretora: nome_corretora, sobre_corretora: sobre_corretora }
  end

  def call
    raise Recusado, 'indisponivel' if @agent.deleted? || !@agent.contratado?

    marca = Autonomia::Agents::Contratados.marca(@agent)
    valores = Autonomia::Agents::Contratados::Contratar.conferir!(account: @agent.account, modelo: marca['modelo'], **@dados)
    # Relida sob a trava: a versão da base, gravada à parte (`Base.semear!`), não pode voltar à que foi lida antes.
    @agent.with_lock do
      raise Recusado, 'indisponivel' if @agent.deleted? || !@agent.contratado?

      nova = Autonomia::Agents::Contratados.marca(@agent).merge(valores)
      @agent.update!(name: valores['nome_agente'],
                     config: @agent.config.to_h.merge(Autonomia::Agents::Contratados::MARCA => nova))
    end
    @agent
  end
end
