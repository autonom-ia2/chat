# #3176 — as chaves de `custom_attributes` do contato que são do sistema, e não da equipe.
#
# - As da WAHA (Waha::ContactChatId::KEYS): o chat id, o jid e o lid com que a WAHA acha a conversa do contato. Sem a
#   definição delas a busca da WAHA deixa de filtrar e pode achar o contato errado.
# - As de controle da Prospecção (Autonomia::Prospecting::ContactConverter): o lead que gravou o contato, o fornecedor,
#   o código do lugar, quem converteu, e as marcas do nome e do cargo que nós escrevemos. A nota e o número de
#   avaliações no Google não estão aqui: servem à equipe e aparecem na ficha com nome em português.
#
# Quem decide o que é interno é esta lista, e só ela: o painel a recebe na resposta da conta (`chaves_internas`) e
# esconde essas chaves de toda tela; a definição de uma delas não é apagada nem muda de chave, tipo ou modelo
# (CampoInternoProtegido); e o escopo `CustomAttributeDefinition.visiveis` as tira do que vai para o Guia, as IAs e a
# importação. Os valores continuam gravados: a WAHA e a Prospecção dependem deles.
#
# Comparação pela chave inteira, nunca por pedaço: `waha_whatsapp_outra` não é interna.
class Relationships::ChavesInternas
  CONVERSOR = Autonomia::Prospecting::ContactConverter

  LISTA = [
    *Waha::ContactChatId::KEYS,
    CONVERSOR::LEAD_ID_KEY,
    CONVERSOR::PROVIDER_KEY,
    CONVERSOR::PROVIDER_PLACE_ID_KEY,
    CONVERSOR::CONVERTED_BY_ID_KEY,
    CONVERSOR::WRITTEN_NAME_KEY,
    CONVERSOR::WRITTEN_JOB_TITLE_KEY
  ].freeze

  def self.interna?(chave)
    LISTA.include?(chave.to_s)
  end

  # Os atributos sem as chaves internas; os demais ficam como estão.
  def self.sem_internas(atributos)
    atributos.to_h.reject { |chave, _valor| interna?(chave) }
  end
end
