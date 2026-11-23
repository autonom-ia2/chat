# O cartão fidelidade de uma pessoa (#3100): o único lugar que grava movimento e saldo. Cada mudança acontece numa
# transação com a linha do saldo travada (SELECT ... FOR UPDATE), então duas mudanças ao mesmo tempo na mesma pessoa
# passam uma de cada vez e o saldo nunca conta errado.
#
# - `entrar`: a compra, o presente, o ajuste para mais. A entrada guarda o que ainda não saiu (`restante`) e quando
#   vence, pela validade do cartão.
# - `sair`: o prêmio, o estorno, o ajuste para menos. Tira das entradas mais antigas primeiro; o estorno tira primeiro
#   da compra que ele desfaz (`de`). O saldo nunca fica negativo: sai no máximo o que a pessoa tem. Com `exige`, recusa
#   (SaldoInsuficiente) quando a pessoa não tem tanto: o prêmio só sai com o cartão completo.
# - `vencer`: leva o que sobrou das entradas vencidas, num movimento "venceu" só.
#
# `antes` e `depois` dizem o saldo da pessoa no começo e agora, para quem chama saber se o cartão completou
# (`completou?`): o gatilho "completou o cartão" sai depois do commit, por quem chamou.
class Fidelidade::Carteira
  class SaldoInsuficiente < StandardError; end

  attr_reader :antes, :programa, :contato

  def initialize(programa, contato)
    @programa = programa
    @contato = contato
  end

  def entrar(tipo:, quantos:, agora: Time.current, **atributos)
    travado do |saldo|
      movimento = criar(tipo: tipo, quantos: quantos, restante: quantos, vence_em: programa.vence_em(agora), **atributos)
      saldo.update!(saldo: saldo.saldo + quantos)
      movimento
    end
  end

  def sair(tipo:, quantos:, de: nil, exige: nil, **atributos)
    travado do |saldo|
      raise SaldoInsuficiente if exige && saldo.saldo < exige

      tirado = [quantos, saldo.saldo].min
      tirar_das_entradas(tirado, de)
      saldo.update!(saldo: saldo.saldo - tirado)
      criar(tipo: tipo, quantos: -tirado, **atributos)
    end
  end

  def vencer(agora)
    travado do |saldo|
      vencidas = movimentos.a_vencer(agora).order(:vence_em, :id).lock.to_a
      total = [vencidas.sum(&:restante), saldo.saldo].min
      vencidas.each { |entrada| entrada.update!(restante: 0) }
      next if total.zero?

      saldo.update!(saldo: saldo.saldo - total)
      criar(tipo: Fidelidade::Movimento::VENCEU, quantos: -total)
    end
  end

  def depois = @saldo&.saldo

  # O saldo cruzou a meta (uma ou mais vezes) desde a primeira mudança desta carteira?
  def completou?
    return false if antes.nil? || depois.nil?

    depois / programa.meta > antes / programa.meta
  end

  private

  def travado
    Fidelidade::Movimento.transaction do
      saldo = saldo_travado
      @antes = saldo.saldo if @antes.nil?
      @saldo = saldo
      yield saldo
    end
  end

  # A linha nasce na primeira mudança, com zero (INSERT ... ON CONFLICT DO NOTHING): duas criações ao mesmo tempo
  # esbarram no índice único e a segunda espera a primeira, sem erro. Depois, a linha é lida já travada.
  def saldo_travado
    chave = { account_id: programa.account_id, programa_id: programa.id, contact_id: contato.id }
    agora = Time.current
    # A linha nova é só a chave com saldo zero; quem muda o saldo é esta classe, com validação.
    Fidelidade::Saldo.insert_all([chave.merge(saldo: 0, created_at: agora, updated_at: agora)], # rubocop:disable Rails/SkipsModelValidations
                                 unique_by: :idx_fidelidade_saldos_pessoa)
    Fidelidade::Saldo.lock.find_by!(chave)
  end

  def movimentos = Fidelidade::Movimento.da_pessoa(programa, contato.id)

  def criar(**atributos)
    Fidelidade::Movimento.create!(account_id: programa.account_id, programa: programa, contact_id: contato.id, **atributos)
  end

  # Tira `quantos` das entradas com resto: primeiro da entrada `de` (o estorno da compra), depois das mais antigas.
  def tirar_das_entradas(quantos, de)
    faltam = quantos
    entradas_em_ordem(de).each do |entrada|
      break if faltam.zero?

      tira = [entrada.restante, faltam].min
      entrada.update!(restante: entrada.restante - tira)
      faltam -= tira
    end
  end

  def entradas_em_ordem(de)
    entradas = movimentos.com_resto.order(:created_at, :id).lock.to_a
    primeira = de && entradas.find { |entrada| entrada.id == de.id }
    primeira ? [primeira, *(entradas - [primeira])] : entradas
  end
end
