# #2881: os modelos de agente prontos por ramo de seguro, nos specs. A conta só pode usar com o pacote `seguros`
# (interruptor AUTONOMIA_PACOTES_ENABLED ligado e o nicho da conta) E com a flag `agente_modelos_seguro`.
module ModelosDeRamoHelper
  def com_pacotes_ligados(&)
    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true', &)
  end

  def conta_de_seguros(conta, perfil: 'corretora')
    conta.update!(internal_attributes: conta.internal_attributes.to_h.merge(
      Autonomia::Agents::Nicho::NICHO_KEY => 'seguros', Autonomia::Agents::Nicho::PERFIL_KEY => perfil
    ))
  end

  def liberar_modelos(conta)
    conta_de_seguros(conta)
    conta.enable_features!(Autonomia::Agents::ModelosDeRamo::FLAG)
  end

  # As prontas do Construtor com a fundação e a F1 (CEP, CNPJ, FIPE, CPF, feriados, cidades, Banco Central...). As
  # fontes de fase posterior (compras do governo, NCM, chuva, transportadoras) ficam desligadas: somem sozinhas.
  def ligar_prontas_do_construtor(conta)
    conta.enable_features!(Autonomia::FerramentasProntas::FLAG, Autonomia::FerramentasProntas::FLAG_CONSULTAS,
                           Autonomia::FerramentasProntas::FLAG_VITRINE, Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
  end

  def modelo_de_ramo(chave = 'seguro_garantia')
    Autonomia::Agents::ModelosDeRamo.buscar(chave)
  end

  # A conversa de criação já aberta com o modelo (a conta precisa poder usar).
  def conversa_com_modelo(conta, chave = 'seguro_garantia', **opcoes)
    Autonomia::Agents::BuildThread.new(account: conta, **opcoes).tap do |conversa|
      conversa.persist_start_options!(type: 'custom', with_knowledge: false, modelo: chave)
      conversa.save!
    end
  end
end
