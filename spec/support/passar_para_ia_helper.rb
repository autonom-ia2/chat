# #1593 — dublês por contrato do que ainda não está na main:
# - Autonomia::Agents::PassarParaIa (PR-B da sessão Agentes IA): `call(conversation:, agent:, por:, motivo:, origem: nil,
#   pedida_por: nil, transfer_id: nil)` -> Resultado (ok?, trocou?, codigo); pedida_por obrigatório com por: :pessoa e
#   proibido com :crm. `destinos_possiveis(conversation)` e `destinos_na_caixa(inbox)` -> Array<Agent>;
# - Crm::Passagens.com_motivo(motivo) { ... } (PR B da #1606).
# Quando cada um entrar, o dublê sai e o spec usa o código real.
module PassarParaIaHelper
  CODIGOS_OK = %i[passou ja_e_o_dono].freeze

  # O Resultado do PassarParaIa, na forma combinada.
  class ResultadoDaIa
    attr_reader :codigo

    def initialize(codigo)
      @codigo = codigo
    end

    def ok?
      CODIGOS_OK.include?(codigo)
    end

    def trocou?
      codigo == :passou
    end
  end

  def dublar_passar_para_ia(destinos: [], codigo: :passou)
    # rubocop:disable RSpec/VerifiedDoubleReference -- a constante chega no PR-B dos Agentes IA
    servico = class_double('Autonomia::Agents::PassarParaIa')
    # rubocop:enable RSpec/VerifiedDoubleReference
    allow(servico).to receive(:destinos_possiveis).and_return(destinos)
    allow(servico).to receive(:destinos_na_caixa).and_return(destinos)
    responder_ia(servico, codigo)
    stub_const('Autonomia::Agents::PassarParaIa', servico)
    servico
  end

  # O serviço passa a responder `codigo`, sempre conferindo os argumentos como o real.
  def responder_ia(servico, codigo)
    allow(servico).to receive(:call) do |**argumentos|
      validar_chamada_da_ia!(argumentos)
      resultado_da_ia(codigo)
    end
  end

  # As regras de argumento do serviço real: por: :pessoa exige pedida_por; por: :crm não aceita.
  def validar_chamada_da_ia!(argumentos)
    raise ArgumentError, 'pedida_por com por: :crm' if argumentos[:por] == :crm && argumentos.key?(:pedida_por)
    raise ArgumentError, 'por: :pessoa sem pedida_por' if argumentos[:por] == :pessoa && argumentos[:pedida_por].nil?
  end

  def resultado_da_ia(codigo)
    ResultadoDaIa.new(codigo)
  end

  # Só o `com_motivo`, que chega no PR B da #1606: roda o bloco e anota o motivo. O resto do Crm::Passagens segue real.
  # Sem a verificação do dublê parcial só enquanto o método não existe. -> a lista dos motivos marcados.
  def dublar_com_motivo
    motivos = []
    without_partial_double_verification do
      allow(Crm::Passagens).to receive(:com_motivo) do |motivo, &bloco|
        motivos << motivo
        bloco.call
      end
    end
    motivos
  end

  def criar_agente_ia(account, nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
end

RSpec.configure { |config| config.include PassarParaIaHelper }
