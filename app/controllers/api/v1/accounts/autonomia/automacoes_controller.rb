# As automações da Automação livre pelo editor (#2414 F5, ADR-001 2.2): o catálogo de passos, a lista, abrir, criar,
# salvar (cada salvar é uma versão nova; a anterior nunca muda), ligar e desligar. O histórico ("O que aconteceu", #2498)
# mostra cada vez que ela rodou, e a lista leva as contagens da semana. O ensaio (#2498) mostra o que ela faria nas
# conversas recentes de quem pede, sem fazer nada.
#
# A automação nasce desligada. Ligar é sempre "assumir e religar": passa a agir como quem está pedindo, se essa pessoa
# pode (D1, F3.7); quem não pode recebe o motivo e nada muda. A receita é conferida pela própria Versao (esquema +
# Autonomia::Automacao::Receita); o erro volta em frase para a pessoa corrigir.
class Api::V1::Accounts::Autonomia::AutomacoesController < Api::V1::Accounts::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao
  FLAG = 'automacao_editor'.freeze
  # Passos nativos de funil: o retorno (G3), que cria pelo crm/follow_ups, o "criar card" (G4) e o "para cada item" (G24).
  PASSOS_DE_FUNIL = %w[retorno card para_cada].freeze

  wrap_parameters false

  # Desligar sempre funciona (D7), mesmo com a flag desligada depois de a automação ter sido ligada.
  before_action :exigir_flag, except: :desligar
  before_action :autorizar
  before_action :carregar_automacao, only: [:show, :update, :ligar, :desligar, :historico, :ensaio]

  # Outra pessoa salvou depois da versão que a tela mostrou (🔴1/🟠3 da qualidade): a tela mostra a versão nova antes
  # de deixar ligar ou salvar.
  rescue_from ::Autonomia::Automacao::Definicao::VersaoMudou do
    render json: { error: I18n.t('autonomia.automacao.editor.versao_mudou'), versao: @automacao.reload.versao_ativa_id },
           status: :conflict
  end

  def passos
    render json: ::Autonomia::Automacao::Catalogo.todos
  end

  # A lista mostra cada automação em frase (Quando → primeiro passo), então leva a receita, e o fato da semana
  # ("Rodou 12 vezes esta semana · 1 parou"), de uma consulta agrupada só.
  def index
    automacoes = escopo.includes(:versao_ativa, :ligada_por).order(:id).to_a
    semana = ::Autonomia::Automacao::Historico.semana(automacoes.map(&:id))
    render json: { automacoes: automacoes.map { |automacao| para_tela(automacao, receita: true).merge(semana: semana[automacao.id]) } }
  end

  def show
    render json: para_tela(@automacao, receita: true)
  end

  def create
    return recusar_funil if sem_funil?(receita)

    automacao = escopo.new(nome: params[:nome], origem: 'manual')
    DEFINICAO.transaction do
      automacao.save!
      automacao.salvar_versao!(receita: receita, autor: Current.user)
    end
    render json: para_tela(automacao, receita: true), status: :created
  rescue ActiveRecord::RecordInvalid => e
    recusar(e.record)
  end

  def update
    conferir_versao!(:base_versao_id) if params.key?(:receita)
    return recusar_funil if params.key?(:receita) && sem_funil?(receita)

    DEFINICAO.transaction do
      @automacao.update!(nome: params[:nome]) if params.key?(:nome)
      @automacao.salvar_versao!(receita: receita, autor: Current.user, base: versao_vista(:base_versao_id)) if params.key?(:receita)
    end
    render json: para_tela(@automacao.reload, receita: true)
  rescue ActiveRecord::RecordInvalid => e
    recusar(e.record)
  end

  def ligar
    conferir_versao!(:versao_id)
    return recusar_funil if sem_funil?(@automacao.versao_ativa&.receita)

    recusa = @automacao.assumir_e_religar!(Current.user, versao_id: versao_vista(:versao_id))
    return render json: para_tela(@automacao) if recusa.nil?

    render json: { error: I18n.t("autonomia.automacao.motivos.#{recusa.motivo}"), problemas: recusa.problemas },
           status: :unprocessable_entity
  end

  def desligar
    @automacao.desligar!
    render json: para_tela(@automacao)
  end

  # Custo da IA e tokens (que dão o custo) seguem o Crm::AiUsageController#com_valores? (#1969): administrador ou financial_view.
  def historico
    com_valores = Current.account_user&.permission_granted?('financial_view') || false
    render json: ::Autonomia::Automacao::Historico.new(automacao: @automacao, usuario: Current.user, com_valores: com_valores,
                                                       pagina: params[:pagina]).resultado
  end

  # A salva ensaia a versão ativa; com `receita` no corpo (o rascunho da tela), ensaia ela. A coleção (`ensaio_novo`) é
  # a automação que ainda não foi salva.
  def ensaio
    rascunho = params.key?(:receita)
    ensaiar(rascunho ? receita : @automacao.versao_ativa&.receita, conferir: rascunho)
  end

  def ensaio_novo
    ensaiar(receita, conferir: true)
  end

  private

  def exigir_flag
    head :not_found unless Current.account.feature_enabled?(FLAG)
  end

  def autorizar
    authorize(DEFINICAO, "#{action_name}?")
  end

  def escopo
    DEFINICAO.where(account: Current.account)
  end

  def carregar_automacao
    @automacao = escopo.find_by(id: params[:id])
    head :not_found if @automacao.nil?
  end

  # A versão que a tela mostrou. Chega como texto ou número; ausente ou inválida vale nil, e com versão ativa isso é
  # VersaoMudou, nunca "salva por cima". Sempre na base 10: "012" é 12, não octal, e "0x1f" é inválida (como no #2460).
  def versao_vista(chave)
    Integer(params[chave].to_s, 10, exception: false)
  end

  # A versão que a tela viu, conferida antes de qualquer outra recusa: quem viu uma versão velha precisa ver a nova
  # primeiro. O motor confere de novo dentro da trava.
  def conferir_versao!(chave)
    raise ::Autonomia::Automacao::Definicao::VersaoMudou if @automacao.versao_ativa_id != versao_vista(chave)
  end

  # A receita é livre de propósito: o esquema e a Receita conferem tudo ao salvar, com erro em frase.
  def receita
    valor = params[:receita]
    valor.respond_to?(:to_unsafe_h) ? valor.to_unsafe_h : valor
  end

  # Passo de funil exige também a chave de funis (D2), de quem salva e de quem liga: as mesmas CHAVES da regra do funil
  # (crm_manage_pipelines ou crm_admin). O catálogo esconder o passo não autoriza nada: a API confere aqui. O gatilho de
  # card (#2499) também pede a chave, e o retorno (G3), que cria pelo crm/follow_ups, e o "criar card" (G4).
  def sem_funil?(receita)
    return false unless receita.is_a?(Hash) && ::Autonomia::Automacao::Receita.esquema_valido?(receita)
    return false if ::Autonomia::Automacao::RegraDoFunil.chave?(Current.account_user)

    de_funil?(receita)
  end

  def de_funil?(receita)
    return true if ::Autonomia::Automacao::Gatilhos.do_card?(receita.dig('gatilho', 'tipo'))

    ::Autonomia::Automacao::Receita.new(receita, conta: Current.account, account_user: Current.account_user).passos.any? do |passo|
      PASSOS_DE_FUNIL.include?(passo['tipo']) || (passo['tipo'] == 'acao' && ::Autonomia::Automacao::AcoesPermitidas.de_funil?(passo['acao']))
    end
  end

  # O rascunho passa pela mesma conferência do salvar (esquema + Receita); a versão salva já passou por ela, e assim o
  # passo de mensagem de uma conta que desligou a flag ainda aparece, com o "não sairia". Só gatilho de conversa: o de
  # card espera a F3 (#2499).
  def ensaiar(receita, conferir:)
    problemas = problemas_do_ensaio(receita, conferir)
    return recusar_ensaio('receita_invalida', problemas) if problemas.any?
    return render(json: recorrente_no_ensaio(receita)) if ::Autonomia::Automacao::Gatilhos.recorrente?(receita.dig('gatilho', 'tipo'))
    return recusar_ensaio('gatilho_de_card') unless ::Autonomia::Automacao::Ensaio.gatilho_suportado?(receita)

    render json: ::Autonomia::Automacao::Ensaio.new(receita: receita, conta: Current.account, usuario: Current.user,
                                                    conversa_id: params[:conversa_id]).resultado
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  # O recorrente (#2635, G7): quantos cards ou contatos a seleção pegaria agora, para o dono ver antes de ligar.
  def recorrente_no_ensaio(receita)
    tipo = receita.dig('gatilho', 'tipo')
    alvo = ::Autonomia::Automacao::Gatilhos.alvo(tipo)
    # O da conta (G7) roda uma vez por ocorrência, sem seleção.
    return { 'recorrente' => { 'alvo' => alvo, 'pegaria' => 1 } } if ::Autonomia::Automacao::Gatilhos.da_conta?(tipo)

    contexto = { user: Current.user, account: Current.account, account_user: Current.account_user }
    selecao = ::Autonomia::Automacao::Tempo::Selecao.new(Current.account, receita['gatilho'])
    { 'recorrente' => { 'alvo' => alvo, 'pegaria' => selecao.quantos_para(contexto) } }
  end

  def problemas_do_ensaio(receita, conferir)
    return [I18n.t('autonomia.automacao.ensaio.sem_receita')] unless receita.is_a?(Hash) && ::Autonomia::Automacao::Receita.esquema_valido?(receita)
    return [] unless conferir

    ::Autonomia::Automacao::Receita.new(receita, conta: Current.account, account_user: Current.account_user).problemas
  end

  def recusar_ensaio(chave, problemas = [])
    render json: { error: I18n.t("autonomia.automacao.ensaio.#{chave}"), problemas: problemas }, status: :unprocessable_entity
  end

  def recusar_funil
    render json: { error: I18n.t('autonomia.automacao.editor.sem_funil') }, status: :unprocessable_entity
  end

  def recusar(registro)
    render json: { error: registro.errors.full_messages.to_sentence, problemas: registro.errors.messages_for(:receita) },
           status: :unprocessable_entity
  end

  def para_tela(automacao, receita: false)
    versao = automacao.versao_ativa
    {
      id: automacao.id, nome: automacao.nome, ativa: automacao.ativa, origem: automacao.origem,
      ligada_por: automacao.ligada_por&.slice(:id, :name), atualizada_em: automacao.updated_at,
      versao: versao && { id: versao.id, numero: versao.numero, autor_id: versao.autor_id, criada_em: versao.created_at,
                          receita: (versao.receita_para_tela if receita) }.compact
    }
  end
end
