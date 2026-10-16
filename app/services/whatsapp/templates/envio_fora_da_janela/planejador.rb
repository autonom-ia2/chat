# O plano de um envio fora da janela (#1587): ver `Whatsapp::Templates::EnvioForaDaJanela`. Só `criar` paga a IA e fala
# com a Meta (`ModeloDoTipo#criar`); o resto lê a lista e os perfis da caixa e, no "compatível", o Jev com cache.
class Whatsapp::Templates::EnvioForaDaJanela::Planejador
  Ponto = Whatsapp::Templates::EnvioForaDaJanela
  Regras = Whatsapp::Templates::EnvioForaDaJanela::Regras
  VERSAO = 1
  DO_TIPO = 'do_tipo'.freeze
  COMPATIVEL = 'compativel'.freeze
  SISTEMA = 'sistema'.freeze
  CONTA = 'conta'.freeze

  # rubocop:disable Metrics/ParameterLists
  def initialize(inbox:, tipo:, com_valor:, ja_recusado:, contato:, criar:)
    @inbox = inbox
    @tipo = Whatsapp::Templates::EnvioForaDaJanela::Tipos.buscar(tipo)
    @com_valor = com_valor ? true : false
    @ja_recusado = ja_recusado ? true : false
    @contato = contato
    @criar = criar
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    return equipe('sem_whatsapp_oficial') unless Whatsapp::Templates::MetaClient.supported?(@inbox)

    impedimento = Regras.impedimento_do_contato(@contato, @tipo.categoria)
    return equipe(impedimento) if impedimento

    proprio = modelo_do_tipo.ler
    do_tipo(proprio) || compativel || sem_aprovado(proprio)
  end

  private

  def modelo_do_tipo
    @modelo_do_tipo ||= Whatsapp::Templates::EnvioForaDaJanela::ModeloDoTipo.new(inbox: @inbox, tipo: @tipo, com_valor: @com_valor)
  end

  def do_tipo(modelo)
    return unless modelo[:status] == :pronto && impedimento_de_uso(modelo[:categoria], sistema: true).nil?

    plano(Ponto::MODELO, escolha: DO_TIPO, origem: SISTEMA, **dados_do_modelo(modelo))
  end

  def compativel
    return if @ja_recusado

    candidatos = Whatsapp::Templates::EnvioForaDaJanela::Candidatos.new(inbox: @inbox, excluir: modelo_do_tipo.nomes_proprios).call
    escolhido = Whatsapp::Templates::EnvioForaDaJanela::Compativel.new(inbox: @inbox, tipo: @tipo, candidatos: candidatos).call
    return if escolhido.nil? || Regras.impedimento_do_contato(@contato, escolhido.categoria)

    dados = { nome: escolhido.nome, idioma: escolhido.idioma, categoria: escolhido.categoria, texto: escolhido.texto,
              campos: escolhido.campos }
    plano(Ponto::MODELO, escolha: COMPATIVEL, origem: escolhido.sistema ? SISTEMA : CONTA, **dados)
  end

  def sem_aprovado(proprio)
    case proprio[:status]
    when :pronto then equipe(impedimento_de_uso(proprio[:categoria], sistema: true))
    when :em_analise then criando(proprio)
    when :ausente then criar_proprio
    else equipe(proprio[:motivo])
    end
  end

  # O envio replaneja com `criar: false`: nunca cria no horário (a criação é do pré-voo).
  def criar_proprio
    return equipe('no_template') unless @criar

    criado = modelo_do_tipo.criar
    case criado[:status]
    when :pronto then do_tipo(criado) || equipe(impedimento_de_uso(criado[:categoria], sistema: true))
    when :em_analise then criando(criado)
    else equipe(criado[:motivo])
    end
  end

  # O modelo do tipo é do sistema: aprovado como MARKETING (a Meta recategoriza), só com a 2ª marca; e o contato.
  def impedimento_de_uso(categoria, sistema:)
    Regras.impedimento(account: @inbox.account, categoria: categoria, sistema: sistema) ||
      Regras.impedimento_do_contato(@contato, categoria)
  end

  def criando(modelo)
    plano(Ponto::CRIANDO, escolha: DO_TIPO, origem: SISTEMA, **dados_do_modelo(modelo))
  end

  def dados_do_modelo(modelo)
    { nome: modelo[:nome], idioma: modelo[:idioma].presence || Whatsapp::Templates::Finalidades::IDIOMA,
      categoria: modelo[:categoria].presence || @tipo.categoria, texto: modelo[:texto], campos: modelo[:campos] }
  end

  def plano(caminho, **dados)
    base.merge('caminho' => caminho).merge(dados.compact.transform_keys(&:to_s))
  end

  def equipe(motivo)
    base.merge('caminho' => Ponto::EQUIPE, 'motivo' => motivo.to_s)
  end

  def base
    { 'versao' => VERSAO, 'tipo' => @tipo.chave, 'opcoes' => @tipo.cobranca? ? { 'com_valor' => @com_valor } : {},
      'ja_recusado' => @ja_recusado }
  end
end
