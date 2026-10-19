# Etiqueta do WhatsApp do celular num contato (#1823, F1b): se ela está posta nele (`vinculada`) e o `at` do último
# vinculada/desvinculada aplicado (`evento_em`), para um evento atrasado do mesmo contato ser descartado. Uma por
# etiqueta do celular e contato. Apagar a etiqueta do celular ou o contato apaga a linha junto.
class Etiquetas::DoCelularNoContato < ApplicationRecord
  self.table_name = 'etiquetas_do_celular_contatos'

  belongs_to :etiqueta_do_celular, class_name: 'Etiquetas::DoCelular'
  belongs_to :contact

  validates :evento_em, presence: true
  validates :vinculada, inclusion: { in: [true, false] }
end
