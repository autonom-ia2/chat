# Ficha do agente para o painel de desempenho (#2251): uma linha por versão; vale a de maior `versao`.
#
# - `catalogo`: os nomes que a tela mostra (temas, marcos, motivos, regras, resultados, origens, quem, cortes).
# - `configuracao`: a regra das contas (pedidos de compra e de dúvida, funil, comparações, cortes, horário comercial,
#   remetentes que falam pelo agente, nomes e definições).
# - `referencias`: o que veio uma vez da conferência e do histórico (valor típico da venda, conferência, conversas de
#   exemplo por [conversation_id, ordem]).
# - `chave_de_leitura` e `instrucao_hash`: ficam vazias na carga manual. A Issue da atualização automática as preenche:
#   a ficha guarda a chave com que a leitura foi feita e o hash da instrução do agente, para saber quando reler.
# Tudo é dado da conta: nada disto vai para o repositório.
class Autonomia::Desempenho::Ficha < ApplicationRecord
  self.table_name = 'autonomia_desempenho_fichas'

  include Autonomia::Desempenho::Sujeito

  validates :versao, numericality: { only_integer: true, greater_than: 0 }
  validates :versao, uniqueness: { scope: %i[account_id sujeito_type sujeito_id] }
  validate :partes_sao_objetos

  def self.vigente(account, tipo, id)
    do_sujeito(account, tipo, id).order(versao: :desc).first
  end

  # O hash da instrução que vai ao modelo hoje (#2301), para saber se a leitura foi feita com outra. Só o agente nosso
  # tem instrução aqui; o robô de outro sistema devolve nil.
  def self.hash_da_instrucao(account, tipo, id)
    return nil unless tipo == 'agente'

    agente = Autonomia::Agents::Agent.where(account_id: account.id).find_by(id: id)
    agente && Digest::SHA256.hexdigest(agente.instrucao_do_sistema.to_s)
  end

  private

  def partes_sao_objetos
    %i[catalogo configuracao referencias].each do |parte|
      errors.add(parte, :invalid) unless public_send(parte).is_a?(Hash)
    end
  end
end
