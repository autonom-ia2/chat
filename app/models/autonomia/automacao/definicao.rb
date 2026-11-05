# Uma automação da conta (#2414, F2 #2452). Nasce desligada (`ativa` false no banco). A receita mora nas versões:
# `salvar_versao!` cria a próxima e passa a ativa para ela; as anteriores nunca mudam.
#
# `ligada_por` é quem ligou: o motor (F3) age como essa pessoa (D1). Sem ela (usuário apagado), a automação não roda
# e pausa; nunca troca para outro usuário.
class Autonomia::Automacao::Definicao < ApplicationRecord
  self.table_name = 'autonomia_automacoes'

  ORIGENS = %w[guia manual receita conversao].freeze

  belongs_to :account
  belongs_to :ligada_por, class_name: 'User', optional: true
  belongs_to :versao_ativa, class_name: 'Autonomia::Automacao::Versao', optional: true
  has_many :versoes, class_name: 'Autonomia::Automacao::Versao', foreign_key: :automacao_id, inverse_of: :automacao,
                     dependent: nil
  has_many :execucoes, class_name: 'Autonomia::Automacao::Execucao', foreign_key: :automacao_id, inverse_of: :automacao,
                       dependent: nil

  validates :nome, presence: true
  validates :origem, inclusion: { in: ORIGENS }
  validate :versao_ativa_desta_automacao

  # O instante em que ficou ligada, a cada vez que liga (religar depois de desligar conta de novo). Os gatilhos de tempo
  # não agem na ocorrência anterior a ele (Tempo.ligada_desde).
  before_save { self.ligada_em = Time.current if ativa && will_save_change_to_ativa? }

  # Desligar sempre funciona (D7, F3.4): quem está no meio para agora, e a próxima rodada de quem já estava na fila
  # também para (o executor confere `ativa`).
  #
  # Sem callback de propósito: a execução órfã (alvo apagado) não passa no `belongs_to`, e desligar não pode falhar por
  # ela. Leva a finalizada_em junto, como o CHECK pede.
  def desligar!
    transaction do
      update!(ativa: false)
      agora = Time.current
      execucoes.abertas.update_all(estado: 'parada', travada_em: nil, finalizada_em: agora, updated_at: agora) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # A versão que a pessoa viu na tela já não é a ativa: outra pessoa salvou no meio. A tela (F5) responde 409 e mostra
  # a versão nova antes de deixar ligar ou salvar.
  class VersaoMudou < StandardError; end

  # Por que não ligou: a chave do motivo (autonomia.automacao.motivos.*) e, quando a receita deixou de rodar, as frases
  # de Receita#problemas, que a tela (F5) mostra no 422.
  Recusa = Struct.new(:motivo, :problemas, keyword_init: true)

  # "Assumir e religar" (F3.7): a automação passa a agir como `usuario`, se ele pode. Nunca liga em nome de quem não
  # pode: devolve a Recusa e não muda nada; ligou, devolve nil. `usuario` é sempre quem está pedindo (o usuário logado):
  # a tela não escolhe outra pessoa, senão alguém com a chave poria o administrador como quem ligou.
  #
  # `versao_id` é a versão que a pessoa viu. Se outra pessoa salvou depois, levanta VersaoMudou: senão A ligaria, com
  # os direitos dela, os passos que B montou e A nunca viu (parecer do Funções, #2462). A receita é conferida de novo
  # na hora de ligar: a lista de ações, o atributo ou a etapa podem ter mudado depois que ela foi salva.
  def assumir_e_religar!(usuario, versao_id:)
    with_lock do
      raise VersaoMudou if versao_ativa_id != versao_id

      recusa = recusa_para_ligar(usuario)
      next recusa if recusa

      update!(ligada_por: usuario, ativa: true)
      nil
    end
  end

  # A automação roda com os direitos de quem a ligou (D1). Se outra pessoa salva uma versão nova, a automação pausa até
  # alguém assumir e religar: senão quem tem menos direitos faria passos com os direitos de quem ligou (parecer do
  # Funções, #2462).
  #
  # `base` é a versão sobre a qual a pessoa editou (nil na primeira). Com ela, quem salva por cima de uma versão que
  # não viu recebe VersaoMudou, em vez de o último a salvar ganhar em silêncio. Sem `base:`, salva sobre a atual.
  def salvar_versao!(receita:, autor: nil, base: :atual)
    with_lock do
      raise VersaoMudou if base != :atual && versao_ativa_id != base

      versao = versoes.create!(account: account, numero: versoes.maximum(:numero).to_i + 1, receita: receita, autor: autor)
      update!(versao_ativa: versao, ativa: ativa && autor.present? && autor.id == ligada_por_id)
      versao
    end
  end

  private

  def recusa_para_ligar(usuario)
    return Recusa.new(motivo: 'sem_versao', problemas: []) unless versao_ativa

    problemas = problemas_da_receita
    return Recusa.new(motivo: 'receita_com_problema', problemas: problemas) if problemas.any?

    self.ligada_por = usuario
    motivo = ::Autonomia::Automacao::Acesso.new(self).motivo
    restore_attributes([:ligada_por_id]) if motivo
    Recusa.new(motivo: motivo, problemas: []) if motivo
  end

  # Fora do esquema, a Receita não sabe dizer o problema passo a passo; vai a frase do motivo.
  def problemas_da_receita
    receita = versao_ativa.receita
    return [I18n.t('autonomia.automacao.motivos.receita_com_problema')] unless ::Autonomia::Automacao::Receita.esquema_valido?(receita)

    ::Autonomia::Automacao::Receita.new(receita, conta: account).problemas
  end

  def versao_ativa_desta_automacao
    errors.add(:versao_ativa, :invalid) if versao_ativa && (versao_ativa.automacao_id != id || versao_ativa.account_id != account_id)
  end
end
