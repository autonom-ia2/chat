# O modo do agente (guiado ou manual) no AgentsController. Em modo guiado, instruction e scaffold vêm do Construtor;
# em manual, a instrução é do dono e o andaime é o genérico do modo manual. A troca guiado -> manual descarta a
# instrução gerada pelo Construtor (IP oculto, #1484), lendo o modo pedido como o banco o grava (revisão adversarial
# do #1492: o enum aceita o inteiro 1 como 'manual').
module Autonomia::ModoDoAgente
  extend ActiveSupport::Concern

  private

  # Em modo guiado, instruction/scaffold vêm do Construtor (Builder) — jamais do controller.
  def apply_manual_scaffold
    @agent.scaffold = self.class::MANUAL_SCAFFOLD if @agent.manual?
  end

  # Ao transicionar um agente GUIADO -> MANUAL, a `instruction` antiga foi gerada pelo Construtor
  # (IP OCULTO) e o jbuilder passa a expô-la em modo manual. Descartamos esse texto gerado antes de
  # qualquer assign: se o usuário mandar a instrução DELE neste request, ela entra logo a seguir via
  # agent_params; se não mandar, fica em branco (nunca vazamos a instrução do Construtor).
  def discard_generated_instruction_on_manual_switch
    @agent.instruction = nil if troca_para_manual?
  end

  def troca_para_manual?
    modo_pedido == 'manual' && @agent.guided?
  end

  # O modo pedido como o banco o grava (revisão adversarial do #1492): o enum aceita `"manual"` e também o inteiro
  # `1`; comparar o texto do parâmetro deixava `{"mode": 1}` trocar para manual sem descartar a instrução gerada.
  def modo_pedido
    valor = params.dig(:agent, :mode)
    ::Autonomia::Agents::Agent.attribute_types['mode'].cast(valor).to_s unless valor.to_s.empty?
  end

  def manual_mode?
    requested = modo_pedido
    return requested == 'manual' if requested.present?

    @agent&.manual? || false
  end
end
