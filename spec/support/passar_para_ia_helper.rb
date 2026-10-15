# #1593 — dublês por contrato do serviço dos Agentes (Autonomia::Agents::PassarParaIa, PR-B da sessão Agentes IA) e do
# registro de passagens do CRM (Crm::Passagens, #1606), até os dois entrarem na main. Os nomes e assinaturas são os
# combinados nas Issues; trocar por chamadas reais quando entrarem.
module PassarParaIaHelper
  def dublar_passar_para_ia(destinos: [], codigo: :passou)
    servico = class_double('Autonomia::Agents::PassarParaIa')
    allow(servico).to receive(:destinos_possiveis).and_return(destinos)
    allow(servico).to receive(:destinos_na_caixa).and_return(destinos)
    allow(servico).to receive(:call).and_return(resultado_da_ia(codigo))
    stub_const('Autonomia::Agents::PassarParaIa', servico)
    servico
  end

  def resultado_da_ia(codigo)
    ok = %i[passou ja_e_o_dono].include?(codigo)
    double('Autonomia::Agents::PassarParaIa::Resultado', ok?: ok, trocou?: codigo == :passou, codigo: codigo)
  end

  def dublar_passagens(ultima_aberta: nil)
    passagens = class_double('Crm::Passagens')
    allow(passagens).to receive(:registrar!)
    allow(passagens).to receive(:com_motivo) { |_motivo, &bloco| bloco.call }
    allow(passagens).to receive(:ultima_aberta).and_return(ultima_aberta)
    stub_const('Crm::Passagens', passagens)
    passagens
  end

  # A ponta de uma passagem como o leitor do #1606 devolve: classe + id identificam; tipo e nome são para a tela.
  def ponta(registro)
    case registro
    when User then double('ponta', classe: 'User', tipo: :pessoa, id: registro.id, nome: registro.name)
    else double('ponta', classe: 'Autonomia::Agents::Agent', tipo: :ia, id: registro.id, nome: registro.name)
    end
  end

  def criar_agente_ia(account, nome)
    Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda o cliente.')
  end
end

RSpec.configure { |config| config.include PassarParaIaHelper }
