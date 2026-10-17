# O catálogo fechado da memória das IAs (#1601): uma linha por (conta, modelo do atributo, chave). A IA não cria chave;
# a operação com chave fora daqui é descartada. Nasce dos campos personalizados da conta (Crm::Memoria::Catalogo) e
# das chaves do sistema; o administrador ajusta cardinalidade, item natural, identidade, obrigatória e validade.
#
# - nivel: cliente (campo do contato), pedido (campo do card), conversa (campo da conversa) ou sistema.
# - cardinalidade: 1, ou N (vários itens no mesmo pedido: os veículos de uma cotação). Com N, cada item é um fato, pelo
#   `item_ref` (o identificador natural do item, como a placa).
# - item_natural: esta chave identifica o item (a placa). identidade: dado de identidade (CPF, e-mail). Nos dois, o
#   valor precisa aparecer na mensagem de prova (A9), senão o fato fica como sugestão.
# - obrigatoria: o pedido precisa dela; entra primeiro no que a IA lê e no "o que falta".
class Crm::MemoriaChave < ApplicationRecord
  self.table_name = 'crm_memoria_chaves'

  NIVEIS = %w[cliente pedido conversa sistema].freeze
  MODELOS = { 'contact_attribute' => 'cliente', 'card_attribute' => 'pedido', 'conversation_attribute' => 'conversa',
              'sistema' => 'sistema' }.freeze

  belongs_to :account

  validates :chave, :attribute_model, presence: true
  validates :attribute_model, inclusion: { in: MODELOS.keys }
  validates :nivel, inclusion: { in: NIVEIS }
  validates :cardinalidade, inclusion: { in: [1, 2] }
  validates :validade_dias, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # 2 = N (vários itens); 1 = um valor só.
  def varios?
    cardinalidade == 2
  end

  def conferir_na_prova?
    identidade? || item_natural?
  end
end
