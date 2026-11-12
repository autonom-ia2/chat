# Os itens do passo "para cada um de uma lista" (#2932), sempre na conta: os cards abertos de uma etapa, os contatos com
# uma etiqueta ou os contatos de um público (os Públicos das campanhas, #1005: as linhas importadas que viraram contato).
# Em ordem de criação, para a rodada que para no meio retomar na mesma ordem.
#
# Quem abre as execuções (FilhasDaLista) confere o alcance de quem ligou e relê do banco, por lote, se o contato recusa
# mensagens ativas ou está bloqueado (Contact.campaign_unreachable, a régua das campanhas): o item que não recebe nada não
# entra. `contar` diz quantos entrariam agora e os primeiros nomes, sem abrir nada: a tela antes de ligar e o ensaio.
class Autonomia::Automacao::ItensDaLista
  # Quantos itens além do teto a contagem lê, no máximo, para dizer quantos ficariam para a próxima vez. O alcance é uma
  # pergunta às políticas por item: a tela espera, e a rodada do motor (FilhasDaLista) usa a mesma conta para parar.
  ALEM_DO_TETO = 300
  PRIMEIROS = 3
  # O público salvo (a importação terminou), como a escolha de público da campanha (CampaignImportsController).
  PUBLICOS_SALVOS = %w[completed completed_with_failures].freeze
  Contagem = Struct.new(:total, :primeiros, :fora_do_teto, keyword_init: true)

  def self.alvo(lista) = lista.to_h['de'] == 'etapa' ? 'Crm::Card' : 'Contact'

  def initialize(conta, lista)
    @conta = conta
    @lista = lista.to_h
  end

  def escopo
    case @lista['de']
    when 'etapa' then @conta.crm_cards.where(stage_id: @lista['etapa_id'], status: :open).includes(:contact).order(:id)
    when 'etiqueta' then @conta.contacts.tagged_with(@lista['etiqueta'], on: :labels).order(:id)
    when 'publico' then @conta.contacts.where(id: contatos_do_publico).order(:id)
    else @conta.contacts.none
    end
  end

  # O contato do item: o próprio contato, ou o do card.
  def self.contato_de(item) = item.is_a?(::Contact) ? item : item.contact

  # O item que não recebe nada da automação: o contato recusou mensagens ativas ou está bloqueado (o já carregado).
  def self.recusado?(item)
    contato = contato_de(item)
    contato.present? && contato.campaign_refusal.present?
  end

  # Os ids dos contatos de `itens` que não recebem nada, relidos do banco agora numa consulta (logo antes de abrir as
  # execuções do lote).
  def self.recusados(itens)
    ids = itens.filter_map { |item| contato_de(item)&.id }
    ::Contact.where(id: ids).campaign_unreachable.pluck(:id).to_set
  end

  def self.nome_de(item) = item.is_a?(::Contact) ? item.name : item.title

  # O público salvo desta conta; outra importação (Importar contatos, a do "para cada item") não é público.
  def self.publico(conta, id)
    importacao = conta.campaign_imports.where(status: PUBLICOS_SALVOS).find_by(id: id)
    importacao if importacao&.audience?
  end

  # Quantos entrariam agora (até o `teto`) para quem `acesso` alcança, e os primeiros nomes (só dos que entram). Lê até
  # `teto + ALEM_DO_TETO` itens.
  def contar(acesso, teto)
    entram = []
    total = 0
    escopo.limit(teto + ALEM_DO_TETO).each do |item|
      next if self.class.recusado?(item) || !acesso.alcanca?(item)

      total += 1
      entram << self.class.nome_de(item) if entram.size < [PRIMEIROS, teto].min
    end
    Contagem.new(total: [total, teto].min, primeiros: entram, fora_do_teto: [total - teto, 0].max)
  end

  private

  # As linhas que viraram contato de um público salvo desta conta.
  def contatos_do_publico
    publico = self.class.publico(@conta, @lista['publico_id'])
    return ::CampaignImportRow.none.select(:contact_id) unless publico

    ::CampaignImportRow.where(campaign_import_id: publico.id).where.not(contact_id: nil).select(:contact_id)
  end
end
