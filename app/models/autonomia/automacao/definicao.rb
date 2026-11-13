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
  # Sem callback de propósito, e com os textos da IA apagados (Execucao.parar_por_fora!). A que esperava fecha com o
  # registro do porquê, no passo da espera (#2750). A que está no meio de uma rodada não ganha registro aqui: o cursor
  # dela não diz em que passo a rodada está; leva o porquê e a rodada para sozinha e o registra (Executor#parou_por_fora).
  # Depois do commit, a cobertura da agente de IA que ainda valia devolve a conversa à pessoa (decisão 18).
  def desligar!
    fechadas = transaction do
      update!(ativa: false)
      ::Autonomia::Automacao::Execucao.parar_por_fora!(execucoes, 'desligada')
    end
    ::Autonomia::Automacao::Cobertura.encerrar(fechadas) if fechadas.any?
    # G55: as execuções fecharam em lote; a campanha da vez confere de novo (desligada, nada sai).
    ::Autonomia::Automacao::CampanhaDaOcorrencia.conferir_automacao(self)
  end

  # O desfazer do Guia (#2889): a automação que o Guia criou sai com o desfazer se ainda não rodou nenhuma vez. Já
  # rodou (ligaram e ela agiu), fica: o histórico aponta para ela, e o desfazer avisa o conflito.
  # Já ligada alguma vez (a pessoa assumiu), também fica: apagar tiraria de quem ligou uma automação que ela aprovou.
  def apagar_ao_desfazer
    with_lock do
      next 'automacao_ja_ligada' if ja_ligada?
      next 'automacao_ja_executada' if execucoes.exists?
      next 'mudou_depois' if versoes.exists?

      destroy!
      nil
    end
  end

  # Ligada agora ou alguma vez (alguém assumiu e ligou).
  def ja_ligada? = ativa || ligada_em.present?

  # O desfazer nunca deixa a automação ligada de novo (#2889): ligar é "assumir" (assumir_e_religar!), com a versão que
  # a pessoa viu e a confirmação dela. Nem troca a versão de uma automação ligada: ela rodaria uma versão que quem ligou
  # não viu.
  def self.recusa_ao_restaurar(antes, atual)
    antes = antes.to_h
    ligada = atual.to_h['ativa'] == true
    return 'ficou_desligada' if antes['ativa'] == true && !ligada

    'automacao_ja_ligada' if ligada && antes.key?('versao_ativa_id')
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

  # A etiqueta do gatilho foi renomeada na conta (G10, Autonomia::Automacao::EtiquetaDoGatilho): a versão nova leva o
  # nome novo e a automação segue como estava, ligada ou não, por quem ligou. Não é edição de pessoa (sem autor), então
  # não pausa como o salvar de outra pessoa. A receita que já não passa na conferência por outro motivo (uma etapa
  # apagada depois de salvar) não ganha versão: ligada, desliga, e religar mostra o problema.
  def seguir_etiqueta!(antiga:, nova:)
    seguiu = with_lock do
      receita = versao_ativa.receita
      next true unless receita.dig('gatilho', 'etiqueta').to_s.casecmp?(antiga)

      versao = versoes.new(account: account, numero: versoes.maximum(:numero).to_i + 1,
                           receita: receita.deep_merge('gatilho' => { 'etiqueta' => nova }))
      versao.save && update!(versao_ativa: versao)
    end
    desligar! if !seguiu && ativa
  end

  private

  def recusa_para_ligar(usuario)
    return Recusa.new(motivo: 'sem_versao', problemas: []) unless versao_ativa

    problemas = problemas_da_receita(usuario)
    return Recusa.new(motivo: 'receita_com_problema', problemas: problemas) if problemas.any?

    self.ligada_por = usuario
    motivo = ::Autonomia::Automacao::Acesso.new(self).motivo
    restore_attributes([:ligada_por_id]) if motivo
    Recusa.new(motivo: motivo, problemas: []) if motivo
  end

  # Fora do esquema, a Receita não sabe dizer o problema passo a passo; vai a frase do motivo.
  def problemas_da_receita(usuario)
    receita = versao_ativa.receita
    return [I18n.t('autonomia.automacao.motivos.receita_com_problema')] unless ::Autonomia::Automacao::Receita.esquema_valido?(receita)

    ::Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account.account_users.find_by(user_id: usuario&.id)).problemas
  end

  def versao_ativa_desta_automacao
    errors.add(:versao_ativa, :invalid) if versao_ativa && (versao_ativa.automacao_id != id || versao_ativa.account_id != account_id)
  end
end
