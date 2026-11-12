# Os contatos em que o Ensaio roda um gatilho de contato (G10, a etiqueta posta ou tirada): contatos reais da conta,
# nunca inventados. Só lê. A mesma interface do ConversasDoEnsaio e do CardsDoEnsaio (#2631).
#
# - Só os que quem ensaia alcança, pela pergunta do motor (Acesso#alcanca?) feita a essa pessoa: a política do contato
#   diz se pode mudá-lo.
# - Com a etiqueta escolhida no gatilho, os que a têm: no "posta", como se ela acabasse de entrar; no "tirada", os que a
#   perderiam, como o "saiu da etapa" do card. Sem etiqueta escolhida, os mais recentes.
# - O contato não tem conversa própria: como o card sem conversa, a da caixa da conversa nova (ConversaNovaNoEnsaio).
class Autonomia::Automacao::ContatosDoEnsaio
  include ::Autonomia::Automacao::ConversaNovaNoEnsaio

  def initialize(gatilho:, conta:, usuario:)
    @gatilho = gatilho
    @conta = conta
    @usuario = usuario
    @account_user = conta.account_users.find_by(user_id: usuario.id)
  end

  def recentes(limite) = contatos.reorder(updated_at: :desc, id: :desc).limit(limite).to_a.select { |contato| alcanca?(contato) }

  # O contato escolhido em "Ensaiar em outro contato"; fora do alcance de quem pede, é como se não existisse.
  def um(id)
    contato = contatos.find(id)
    raise ActiveRecord::RecordNotFound unless alcanca?(contato)

    contato
  end

  # O que a tela mostra: o id e o nome do contato no lugar do número da conversa.
  def base(contato) = { conversa_id: contato.id, nome: contato.name, ultima_atividade: contato.updated_at }

  # O gatilho de contato não tem mensagem nem fato para o Contexto.
  def gatilho_de(_contato) = [nil, nil]

  def motivo(_contato, _mensagem, _fato) = nil

  private

  def contatos
    etiqueta = @gatilho['etiqueta']
    etiqueta.present? ? @conta.contacts.tagged_with(etiqueta, on: :labels) : @conta.contacts
  end

  def alcanca?(contato) = ContactPolicy.new(contexto, contato).update?

  def contexto = { user: @usuario, account: @conta, account_user: @account_user }
end
