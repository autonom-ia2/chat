# #2568 P7: a Automação livre que está agindo AGORA, só durante o pedido que o passo "ação" faz pela porta da frente
# (AcoesDoMotor#requisitar, pela ChamadaInterna, como quem a ligou).
#
# Não é a Cadeia. A cadeia viaja no evento e é retomada em todos os listeners: a Atribuição, o agente de IA ou a IA do
# funil que agem depois herdam `automacao:X` como último da cadeia sem que a automação tenha feito aquilo. A cadeia
# serve ao anti-laço; quem assina a mudança é o ato.
#
# Vive fora do `Current` pelo mesmo motivo da cadeia: o pedido de dentro mexe no `Current`.
class Autonomia::Automacao::Ato
  thread_mattr_accessor :automacao_id_atual, instance_accessor: false

  class << self
    def automacao_id
      automacao_id_atual
    end

    def da(automacao_id)
      anterior = automacao_id_atual
      self.automacao_id_atual = automacao_id
      yield
    ensure
      self.automacao_id_atual = anterior
    end
  end
end
