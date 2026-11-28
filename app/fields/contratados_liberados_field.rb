require 'administrate/field/base'

# A liberação dos agentes contratados da conta (#3270), um cartão por modelo do catálogo, sem <select>. `data` é a
# lista das chaves liberadas (Autonomia::Agents::Contratados::Liberacao.modelos). Só o super admin vê e grava.
class ContratadosLiberadosField < Administrate::Field::Base
  def self.permitted_attribute(attr, _options = nil)
    { attr => [] }
  end

  # Os modelos do catálogo, na ordem dele: só eles viram cartão (e só eles são aceitos ao gravar).
  def modelos
    Autonomia::Agents::Contratados::MODELOS.keys
  end

  def liberado?(chave)
    Array(data).include?(chave)
  end
end
