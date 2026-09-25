# Qualificação do sócio na Receita, em tabela fechada. key é a forma normalizada que a regra do dono compara; label é o
# rótulo que a tela mostra. Qualificação fora da tabela mantém o texto da fonte, aparado.
module Autonomia::Prospecting::Research::Qualification
  LABELS = {
    'SOCIO ADMINISTRADOR' => 'Sócio-Administrador',
    'SOCIO' => 'Sócio',
    'TITULAR' => 'Titular',
    'TITULAR PESSOA FISICA RESIDENTE OU DOMICILIADO NO BRASIL' => 'Titular',
    'EMPRESARIO INDIVIDUAL' => 'Empresário Individual',
    'PROPRIETARIO' => 'Proprietário',
    'ACIONISTA CONTROLADOR' => 'Acionista Controlador',
    'ADMINISTRADOR' => 'Administrador',
    'DIRETOR' => 'Diretor',
    'PRESIDENTE' => 'Presidente',
    'CEO' => 'CEO',
    'PROCURADOR' => 'Procurador',
    'REPRESENTANTE LEGAL' => 'Representante Legal',
    'CONSELHEIRO DE ADMINISTRACAO' => 'Conselheiro de Administração'
  }.freeze

  module_function

  def key(raw) = Autonomia::Prospecting::Research::Normalization.key(raw)

  def label(raw)
    LABELS.fetch(key(raw)) { Autonomia::Prospecting::Research::Normalization.squish(raw) }
  end
end
