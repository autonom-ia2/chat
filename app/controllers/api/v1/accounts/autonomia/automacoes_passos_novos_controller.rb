# O que a tela dos passos novos da Automação livre pergunta ao servidor enquanto a pessoa monta (#2932, #2934):
# - `contar_lista`: quantos entrariam hoje no "fazer para cada um de uma lista", pela mesma régua do motor
#   (ItensDaLista#contar: bloqueados fora, só quem a pessoa alcança), até o teto. A lista passa antes pela conferência do
#   salvar (PassoRepetirLista.da_lista): a etapa, a etiqueta ou o público precisam ser da conta e a pessoa precisa poder
#   lê-los.
# - `consultas_prontas`: as consultas prontas do "buscar em outro sistema" (ConsultasProntas), com o que cada uma pede,
#   os dados que devolve com o rótulo pronto e, na que a conta não pode usar, o que falta.
# - `testar_consulta`: o "Fazer um teste" do "buscar em outro sistema", e o "Buscar agora" do ensaio. Busca de verdade.
#   Na consulta pronta, pela mesma Execucao dos agentes (ConsultaPronta), com o exemplo que a pessoa escreveu: gasta o
#   limite do dia da conta naquela consulta, como o "Experimente" da vitrine. Em outro endereço, pela mesma ConsultaDeFora
#   do motor (só https, endereço interno recusado depois de resolver o nome, prazo curto), e volta os dados simples da
#   resposta com um rótulo do dia a dia para cada um (RotulosDaConsulta, pela IA da conta). Outro endereço pede a chave
#   de integrações, como montar o passo. Nada é gravado; o endereço e o exemplo não vão para log.
#
# Montar pede `automation_manage` (DefinicaoPolicy). Só com as duas flags: a do editor e a dos passos novos.
class Api::V1::Accounts::Autonomia::AutomacoesPassosNovosController < Api::V1::Accounts::BaseController
  DEFINICAO = ::Autonomia::Automacao::Definicao
  CHAVE_DE_INTEGRACOES = 'integration_manage'.freeze
  VALOR_MAXIMO = 255

  wrap_parameters false

  before_action :exigir_flags
  before_action :autorizar

  def contar_lista
    lista = valor_livre(params[:lista]).to_h
    problemas = ::Autonomia::Automacao::PassoRepetirLista.da_lista(params[:passo_id].to_s, lista, conferencia)
    return render(json: { error: problemas.first, problemas: problemas }, status: :unprocessable_entity) if problemas.any?

    teto = params[:teto].to_i.clamp(1, ::Autonomia::Automacao::RepetirLista::TETO_MAXIMO)
    contagem = ::Autonomia::Automacao::ItensDaLista.new(Current.account, lista).contar(acesso, teto)
    render json: contagem.to_h.merge(teto: teto)
  end

  def consultas_prontas
    render json: { consultas: ::Autonomia::Automacao::ConsultasProntas.para_tela(Current.account) }
  end

  def testar_consulta
    fonte = valor_livre(params[:fonte]).to_h
    return testar_pronta(fonte) if fonte['de'] == ::Autonomia::Automacao::PassoConsultar::PRONTA
    return head(:forbidden) unless Current.account_user.permission_granted?(CHAVE_DE_INTEGRACOES)

    testar_endereco(fonte['url'].to_s)
  end

  private

  # O endereço próprio (avançado, só com a chave de integrações): busca de verdade e sugere o nome de cada dado.
  def testar_endereco(url)
    motivo = ::Autonomia::Automacao::ConsultaDeFora.problema_do_endereco(url)
    return render(json: falhou(motivo), status: :unprocessable_entity) if motivo

    resposta = ::Autonomia::Automacao::ConsultaDeFora.new(url).buscar
    return render(json: falhou(resposta.motivo).merge(codigo: resposta.codigo)) unless resposta.ok?

    render json: { ok: true, ms: resposta.ms, dados: dados_para_tela(resposta.dados) }
  end

  # A consulta pronta com o exemplo de cada entrada. Volta cada dado com o rótulo pronto e o valor de agora.
  def testar_pronta(fonte)
    pronta = ::Autonomia::Automacao::ConsultasProntas.buscar(fonte['consulta'])
    return render(json: falhou('consulta_pronta_desligada'), status: :unprocessable_entity) unless pronta

    exemplos = fonte['exemplos'].to_h.transform_values { |valor| valor.to_s.first(VALOR_MAXIMO) }
    resposta = ::Autonomia::Automacao::ConsultaPronta.new(Current.account, pronta, exemplos).buscar
    return render(json: falhou(resposta.motivo)) unless resposta.ok?

    dados = resposta.dados.map do |caminho, valor|
      { caminho: caminho, valor: valor, rotulo: ::Autonomia::Automacao::ConsultasProntas.rotulo_do_dado(pronta, caminho) }
    end
    render json: { ok: true, ms: resposta.ms, dados: dados }
  end

  def exigir_flags
    conta = Current.account
    ligadas = conta.feature_enabled?(::Api::V1::Accounts::Autonomia::AutomacoesController::FLAG) &&
              ::Autonomia::Automacao::PassosNovos.ligados?(conta)
    head :not_found unless ligadas
  end

  def autorizar
    authorize(DEFINICAO, "#{action_name}?")
  end

  def conferencia
    ::Autonomia::Automacao::PassosNovos::Conferencia.new(conta: Current.account, account_user: Current.account_user, alvo: nil,
                                                         dentro: false)
  end

  # Quem monta alcança o item? A mesma pergunta do motor, feita a quem pede (o ensaio da automação nova faz igual).
  def acesso = ::Autonomia::Automacao::Acesso.new(DEFINICAO.new(account: Current.account, ligada_por: Current.user))

  # A lista e a fonte são livres de propósito: a conferência do passo diz o que falta, em frase.
  def valor_livre(valor) = valor.respond_to?(:to_unsafe_h) ? valor.to_unsafe_h : valor

  # Cada dado simples com o caminho (o que o passo guarda), o valor de agora (para a pessoa reconhecer) e o rótulo do dia
  # a dia (o nome que a tela sugere; a pessoa troca).
  def dados_para_tela(dados)
    achados = ::Autonomia::Automacao::ConsultaDeFora.achatar(dados)
    rotulos = ::Autonomia::Automacao::RotulosDaConsulta.new(Current.account).para(achados.pluck(:caminho))
    achados.map { |achado| { caminho: achado[:caminho], valor: achado[:valor].to_s.first(VALOR_MAXIMO), rotulo: rotulos[achado[:caminho]] } }
  end

  def frase(motivo) = I18n.t("autonomia.automacao.motivos.#{motivo}")

  def falhou(motivo) = { ok: false, motivo: motivo, error: frase(motivo) }
end
