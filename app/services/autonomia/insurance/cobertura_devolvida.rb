# O QUE A SEGURADORA COTOU DE FATO, EM PORTUGUÊS PARA O MODELO (chat#585).
#
# A oferta traz `coverage` com as palavras da seguradora (adapters#75: "Plano 2 - 500km", "Não", "30 Dias"), e as
# CHAVES EM SNAKE_CASE: o `Connector::Http` normaliza a resposta inteira (`rentalCar` chega `rental_car`). Ler as
# chaves do adapter como ele as escreve descartaria tudo sem erro nenhum — foi o que a sonda de 22/09 pegou no
# `notFound` da busca do segurado.
# Aqui cada campo ganha o nome que o especialista entende e o valor em reais escrito como a conferência da fala
# lê ("R$ 500.000,00"): é com essa linha que ele compara o que foi pedido com o que voltou, e é por ela que a
# conferência autoriza o valor que a Lia repassar.
#
# SÓ OS CAMPOS CONHECIDOS são guardados (`CAMPOS`): o que vier a mais do adapter não viaja por aqui sem nome.
module Autonomia::Insurance::CoberturaDevolvida
  ROTULOS = {
    'assistance' => 'assistência',
    'rental_car' => 'carro reserva',
    'glass' => 'vidros',
    'property_damage' => 'danos materiais',
    'bodily_injury' => 'danos corporais',
    'moral_damage' => 'danos morais',
    'death_accident' => 'morte por acidente',
    'disability_accident' => 'invalidez por acidente',
    'deductible_type' => 'tipo de franquia',
    'deductible' => 'franquia',
    'deductible_amount' => 'valor da franquia',
    'referenced_value_percent' => 'tabela FIPE',
    'coverage_type' => 'tipo de cobertura',
    'extra_expenses' => 'despesas extraordinárias',
    'quick_repair' => 'reparo rápido',
    'tire_and_wheel' => 'proteção de pneus e rodas'
  }.freeze
  CAMPOS = ROTULOS.keys.freeze
  EM_REAIS = %w[property_damage bodily_injury moral_damage death_accident disability_accident deductible_amount].freeze
  PERCENTUAL = %w[referenced_value_percent].freeze

  module_function

  # -> só os campos conhecidos, ou nil quando não sobra nenhum.
  def guardavel(coverage)
    return nil unless coverage.is_a?(Hash)

    conhecidos = coverage.to_h.stringify_keys.slice(*CAMPOS).reject { |_, valor| valor.nil? || valor == '' }
    conhecidos.presence
  end

  # -> "carro reserva: Não; danos materiais: R$ 500.000,00; ..." na ordem de `ROTULOS`, ou nil.
  def texto(cobertura)
    return nil unless cobertura.is_a?(Hash)

    itens = CAMPOS.filter_map { |campo| cobertura.key?(campo) ? "#{ROTULOS[campo]}: #{valor(campo, cobertura[campo])}" : nil }
    itens.presence&.join('; ')
  end

  def valor(campo, bruto)
    return (bruto ? 'sim' : 'não') if [true, false].include?(bruto)
    return reais(bruto) if EM_REAIS.include?(campo) && bruto.is_a?(Numeric)
    return "#{bruto.to_s.delete_suffix('.0')}%" if PERCENTUAL.include?(campo) && bruto.is_a?(Numeric)

    bruto.to_s
  end

  def reais(numero)
    ActiveSupport::NumberHelper.number_to_currency(numero, unit: 'R$ ', separator: ',', delimiter: '.', precision: 2)
  end
end
