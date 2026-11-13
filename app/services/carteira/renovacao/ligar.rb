# A apólice nova se liga à que ela renovou (E5, #2898), e a anterior fica renovada: o card de renovação aberto fecha
# como ganho e o seguro é acertado por ele aqui mesmo (Carteira::Renovacao::Fechar.pelo_card), sem esperar o ouvinte do
# card; sem card aberto, o seguro é marcado direto. A anterior fica travada, e o card dela também, na mesma ordem da
# gaveta.
#
# `com(anterior)`: quem trouxe a apólice disse qual ela renovou (a apólice nova feita à mão).
#
# `sozinha`: ninguém disse. A seguradora e o número NÃO entram na conta: a renovação pode ir para outra seguradora, com
# outro número. Liga quando há uma candidata, e só uma; com duas, não escolhe (a tela pergunta). É candidata a apólice
# da mesma conta que tem:
# - o mesmo segurado: a mesma pessoa e a mesma empresa (ou as duas sem empresa);
# - o mesmo ramo, e um ramo conhecido (`outro` é "não sei": não liga);
# - o mesmo item, quando as duas dizem qual é (comparado sem espaço, caixa, acento nem pontuação); a que não diz o
#   item não impede;
# - a vigência emendada: a nova começa até TOLERANCIA dias antes ou depois do fim da anterior, e termina depois dela.
#   Sem o começo da nova não há como saber;
# - e ainda espera renovação: não foi cancelada, ninguém disse "não renovou" e nenhuma outra apólice já a renovou. A
#   que já está como "Renovou" e ainda não tem a apólice nova é candidata: é o caso mais comum.
#
# Tudo numa transação própria: a ligação, o passo da história e o desfecho da anterior entram juntos ou não entram.
class Carteira::Renovacao::Ligar
  # Quantos dias o começo da apólice nova pode ficar longe do fim da anterior.
  TOLERANCIA = 30
  RAMO_DESCONHECIDO = 'outro'.freeze
  PASSO = 'apolice_nova'.freeze

  def initialize(nova, user: nil)
    @nova = nova
    @user = user
  end

  # anotar: a história da apólice nova ganha "Apólice nova guardada. A anterior era a ...". Quem já anotou na chegada
  # (Carteira::Guardar com `chegada: 'apolice_nova'`) passa false.
  def com(anterior, anotar: true)
    Carteira::Apolice.transaction(requires_new: true) do
      @nova.update!(apolice_anterior: anterior)
      @nova.eventos.create!(tipo: PASSO, quando: Time.current, user: @user, valores: { anterior: anterior.numero }) if anotar
      renovar(anterior)
    end
    @nova
  end

  # A apólice anterior a que se ligou, ou nil quando não há uma candidata só.
  def sozinha
    return if @nova.apolice_anterior_id

    candidatas = self.class.candidatas(@nova)
    return unless candidatas.one?

    com(candidatas.first)
    candidatas.first
  end

  def self.candidatas(nova)
    comeca = nova.inicio_vigencia
    return [] if comeca.nil? || nova.cancelado_em || nova.tipo == RAMO_DESCONHECIDO

    esperam_renovacao(nova).where(fim_vigencia: (comeca - TOLERANCIA)..(comeca + TOLERANCIA))
                           .where(fim_vigencia: ...nova.fim_vigencia).order(:id).select { |anterior| mesmo_item?(anterior, nova) }
  end

  # As outras apólices do mesmo segurado e do mesmo ramo que ainda esperam renovação.
  def self.esperam_renovacao(nova)
    da_conta = Carteira::Apolice.where(account_id: nova.account_id)
    da_conta.where(nova.slice(:contact_id, :company_id, :tipo)).where(cancelado_em: nil, nao_renovou_em: nil)
            .where.not(id: nova.id).where.not(id: da_conta.where.not(apolice_anterior_id: nil).select(:apolice_anterior_id))
  end

  def self.mesmo_item?(uma, outra)
    itens = [uma.bem, outra.bem].map { |bem| Carteira::Chave.seguradora(bem) }
    itens.any?(&:empty?) || itens.uniq.one?
  end

  private

  def renovar(anterior)
    anterior.with_lock do
      next if anterior.renovado_em || anterior.nao_renovou_em

      card = anterior.crm_card
      next sem_card(anterior) if card.nil? || anterior.renovacao_card_removido_em

      card.with_lock do
        card.open? ? Carteira::Renovacao::Fechar.pelo_card(anterior, card, Carteira::Renovacao::Fechar::GANHO, user: @user) : sem_card(anterior)
      end
    end
  end

  def sem_card(anterior)
    Carteira::Renovacao::Desfecho.new(anterior, user: @user).renovou_sem_card
  end
end
