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
# A etiqueta sai do nome: "lista-email-" + o nome em minúsculas, sem acento e com hífen (`parameterize`), "Dicas do
# mês" vira "lista-email-dicas-do-mes". O prefixo separa a etiqueta da lista das etiquetas de atendimento: criar a
# lista "VIP" não manda e-mail para quem já tinha a etiqueta "vip".
#
# A lista nova nasce vazia, sempre com etiqueta nova. Se o título já é de uma etiqueta da conta (a lista foi apagada e
# a etiqueta ficou, ou alguém a criou antes da trava do prefixo) ou já está em algum contato (a etiqueta do contato
# aceita qualquer nome, sem passar pela tela de etiquetas), a lista ganha um sufixo ("lista-email-dicas-do-mes-2"):
# ninguém entra numa lista sem alguém o ter posto nela.
#
# Trocar o nome da lista não troca a etiqueta: renomear a etiqueta reescreveria a de cada contato (Labels::UpdateJob).
# Apagar a lista não apaga a etiqueta; apagar a etiqueta apaga a lista (Label has_one :email_list, dependent: :destroy,
# em EmailLists::LabelList). Nos dois casos o rascunho com a lista sai dela antes, sob a trava de envio, e perde os
# pendentes dela: a chave do banco (SET NULL) só tiraria a lista e deixaria os pendentes.
class EmailList < ApplicationRecord
  PREFIXO_DA_ETIQUETA = 'lista-email'.freeze
  TAMANHO_MAXIMO = 80
  # A campanha agendada, em envio ou pausada ficaria sem lista no meio do caminho: a lista dela não sai.
  CAMPANHAS_EM_USO = %i[scheduled sending paused].freeze

  belongs_to :account
  belongs_to :label, inverse_of: :email_list
  # A chave do banco (SET NULL) é a rede de segurança; quem tira a campanha da lista é o before_destroy.
  has_many :email_campaigns, dependent: nil, inverse_of: :email_list

  before_destroy :soltar_as_campanhas

  before_validation { self.name = name.to_s.squish }

  validates :name, presence: true, length: { maximum: TAMANHO_MAXIMO }, uniqueness: { scope: :account_id }
  validate :etiqueta_da_mesma_conta
  validate :nome_de_uma_lista_so

  # Cria a lista e uma etiqueta nova para ela. Devolve a lista, salva ou com os erros.
  #
  # Dois pedidos ao mesmo tempo com o mesmo nome passam juntos pela conferência (titulo_livre e as validações) e um
  # deles bate no índice único (da etiqueta ou do nome da lista): esse volta como nome repetido, sem etiqueta sobrando.
  def self.criar(account:, name:)
    lista = new(account: account, name: name)
    titulo = titulo_da_etiqueta(lista.name)
    return lista.tap { |invalida| invalida.errors.add(:name, invalida.name.blank? ? :blank : :invalid) } if titulo.nil?

    transaction do
      lista.label = account.labels.create!(title: titulo_livre(account, titulo), show_on_sidebar: false, da_lista_de_email: true)
      raise ActiveRecord::Rollback unless lista.save
    end
    lista
  rescue ActiveRecord::RecordNotUnique
    lista.tap { |repetida| repetida.errors.add(:name, :taken) }
  end

  # nil quando o nome não tem letra nem número que sobre ("!!!").
  def self.titulo_da_etiqueta(nome)
    parte = nome.to_s.parameterize
    "#{PREFIXO_DA_ETIQUETA}-#{parte}" if parte.present?
  end

  # O título, ou o primeiro com sufixo (-2, -3...) que não é de etiqueta da conta nem está em contato dela.
  def self.titulo_livre(account, base)
    (1..).each do |numero|
      titulo = numero == 1 ? base : "#{base}-#{numero}"
      return titulo unless titulo_ocupado?(account, titulo)
    end
  end

  def self.titulo_ocupado?(account, titulo)
    account.labels.exists?(title: titulo) || account.contacts.tagged_with(titulo, on: :labels).exists?
  end

  # Quantos estão em cada lista e quantos receberiam, em duas consultas para todas as listas (a tela abre com a lista
  # inteira). => { lista.id => { contatos: 3, recebem: 2 } }
  #
  # O mesmo critério de EmailList#contatos: `tagged_with` casa o nome sem diferença de maiúscula (ILIKE; o
  # acts-as-taggable roda sem strict_case_match), e o título da etiqueta já é minúsculo (Label). Contato com "Lista-X"
  # e "lista-x" conta uma vez.
  def self.contagens(account, listas)
    titulos = listas.map { |lista| lista.label.title }
    # O GROUP BY vai como SQL: o nó do Arel ganharia o apelido do SELECT da contagem dentro do próprio GROUP BY.
    por_etiqueta = account.contacts.joins(:labels).where(ActsAsTaggableOn::Tag.arel_table[:name].lower.in(titulos))
                          .group(Arel.sql('LOWER(tags.name)'))
    contatos = por_etiqueta.distinct.count(:id)
    recebem = elegiveis_de(por_etiqueta).distinct.count(:id)
    listas.to_h do |lista|
      [lista.id, { contatos: contatos.fetch(lista.label.title, 0), recebem: recebem.fetch(lista.label.title, 0) }]
    end
  end

  def self.elegiveis_de(contatos)
    contatos.not_opted_out.where.not(email: [nil, ''])
  end

  # Quem está na lista agora: os contatos da conta com a etiqueta. `distinct`: o contato com a etiqueta escrita de dois
  # jeitos ("Lista-X" e "lista-x", duas tags que casam) viria duas vezes.
  def contatos
    account.contacts.tagged_with(label.title, on: :labels).distinct
  end

  # Quem receberia agora: com e-mail e sem ter pedido para não receber. O descadastro e o bloqueio (EmailSuppression)
  # ficam para o envio, que os grava como `suppressed`.
  def elegiveis
    self.class.elegiveis_de(contatos)
  end

  # Roda o bloco com a trava de envio de cada campanha que usa a lista, em ordem de id (a mesma ordem em todo lugar,
  # para dois processos não se travarem um ao outro). Dentro dela o estado das campanhas não muda.
  def com_as_campanhas_travadas(campanhas = email_campaigns.order(:id).to_a, &)
    return yield if campanhas.empty?

    campanhas.first.with_delivery_lock { com_as_campanhas_travadas(campanhas.drop(1), &) }
  end

  # Roda o bloco (apagar a lista ou a etiqueta dela) sob a trava das campanhas, só se nenhuma está em uso: nenhuma é
  # agendada ou sai entre a conferência e o bloco. => false quando alguma está em uso, sem rodar o bloco.
  def sem_campanha_em_uso
    com_as_campanhas_travadas do
      next false if email_campaigns.exists?(status: CAMPANHAS_EM_USO)

      yield
      true
    end
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

  # Dois nomes que dariam a mesma etiqueta ("Dicas do mês" e "dicas do mes") seriam duas listas com o mesmo nome na tela.
  def nome_de_uma_lista_so
    titulo = self.class.titulo_da_etiqueta(name)
    return if titulo.nil? || errors.of_kind?(:name, :taken)

    outros = self.class.where(account_id: account_id).where.not(id: id).pluck(:name)
    errors.add(:name, :taken) if outros.any? { |outro| self.class.titulo_da_etiqueta(outro) == titulo }
  end
end
