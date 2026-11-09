# == Schema Information
#
# Table name: email_lists
#
#  id         :bigint           not null, primary key
#  name       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  label_id   :bigint           not null
#
# Indexes
#
#  index_email_lists_on_account_id_and_name  (account_id,name) UNIQUE
#  index_email_lists_on_label_id             (label_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (label_id => labels.id) ON DELETE => cascade
#

# Lista de e-mail da conta (G52, #2760): um nome ("Dicas do mês") e, por baixo, uma etiqueta. Estar na lista é ter a
# etiqueta; a campanha de e-mail com a lista vai para quem a tem na hora do envio (EmailLists::Recipients).
#
# A etiqueta sai do nome, sempre igual: "lista-email-" + o nome em minúsculas, sem acento e com hífen
# (`parameterize`), "Dicas do mês" vira "lista-email-dicas-do-mes". O prefixo separa a etiqueta da lista das etiquetas
# de atendimento: criar a lista "VIP" não manda e-mail para quem já tinha a etiqueta "vip". Se a etiqueta já existe
# (a lista foi apagada e criada de novo), ela é reaproveitada, com quem já estava nela.
#
# Trocar o nome da lista não troca a etiqueta: renomear a etiqueta reescreveria a de cada contato (Labels::UpdateJob).
# Apagar a lista não apaga a etiqueta; apagar a etiqueta apaga a lista (Label has_one :email_list, dependent: :destroy,
# em EmailLists::LabelList). Nos dois casos o rascunho com a lista sai dela antes, sob a trava de envio, e perde os
# pendentes dela: a chave do banco (SET NULL) só tiraria a lista e deixaria os pendentes.
class EmailList < ApplicationRecord
  PREFIXO_DA_ETIQUETA = 'lista-email'.freeze
  TAMANHO_MAXIMO = 80

  belongs_to :account
  belongs_to :label, inverse_of: :email_list
  # A chave do banco (SET NULL) é a rede de segurança; quem tira a campanha da lista é o before_destroy.
  has_many :email_campaigns, dependent: nil, inverse_of: :email_list

  before_destroy :soltar_as_campanhas

  before_validation { self.name = name.to_s.squish }

  validates :name, presence: true, length: { maximum: TAMANHO_MAXIMO }, uniqueness: { scope: :account_id }
  validate :etiqueta_da_mesma_conta
  validate :etiqueta_de_uma_lista_so

  # Cria a lista e a etiqueta dela (ou reaproveita a etiqueta). Devolve a lista, salva ou com os erros.
  def self.criar(account:, name:)
    lista = new(account: account, name: name)
    titulo = titulo_da_etiqueta(lista.name)
    return lista.tap { |invalida| invalida.errors.add(:name, invalida.name.blank? ? :blank : :invalid) } if titulo.nil?

    transaction do
      lista.label = account.labels.find_or_create_by!(title: titulo) { |etiqueta| etiqueta.show_on_sidebar = false }
      raise ActiveRecord::Rollback unless lista.save
    end
    lista
  end

  # nil quando o nome não tem letra nem número que sobre ("!!!").
  def self.titulo_da_etiqueta(nome)
    parte = nome.to_s.parameterize
    "#{PREFIXO_DA_ETIQUETA}-#{parte}" if parte.present?
  end

  # Quem está na lista agora: os contatos da conta com a etiqueta.
  def contatos
    account.contacts.tagged_with(label.title, on: :labels)
  end

  # Quem receberia agora: com e-mail e sem ter pedido para não receber. O descadastro e o bloqueio (EmailSuppression)
  # ficam para o envio, que os grava como `suppressed`.
  def elegiveis
    contatos.not_opted_out.where.not(email: [nil, ''])
  end

  # Roda o bloco com a trava de envio de cada campanha que usa a lista, em ordem de id (a mesma ordem em todo lugar,
  # para dois processos não se travarem um ao outro). Dentro dela o estado das campanhas não muda.
  def com_as_campanhas_travadas(campanhas = email_campaigns.order(:id).to_a, &)
    return yield if campanhas.empty?

    campanhas.first.with_delivery_lock { com_as_campanhas_travadas(campanhas.drop(1), &) }
  end

  private

  # O rascunho sai da lista e perde os pendentes dela (EmailLists::Recipients#sync! sem lista). A campanha agendada,
  # em envio ou pausada (o painel recusa apagar a lista dela; só a exclusão da etiqueta chega aqui) fica com os
  # destinatários da última montagem: o SET NULL só tira a referência.
  def soltar_as_campanhas
    com_as_campanhas_travadas do
      email_campaigns.reload.each { |campanha| campanha.update!(email_list: nil) if campanha.draft? }
    end
  end

  def etiqueta_da_mesma_conta
    return if label.blank? || label.account_id == account_id

    errors.add(:label, :invalid)
  end

  # Dois nomes que dão a mesma etiqueta ("Dicas do mês" e "dicas do mes") seriam a mesma lista.
  def etiqueta_de_uma_lista_so
    return if label_id.blank? || errors.of_kind?(:name, :taken) || !self.class.where(label_id: label_id).where.not(id: id).exists?

    errors.add(:name, :taken)
  end
end
