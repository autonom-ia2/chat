# O modelo reaproveitável de um tipo numa caixa (#1587): um por (caixa, tipo), nome estável (`Tipos.nome`).
# - cobrança: o pronto fixo de `Finalidades` (momento do tipo, com ou sem valor), lido e criado pelo `Garantir`;
# - os outros: a IA escreve para o negócio (`Ai::Redacao::Escrever`, canal `whatsapp_modelo`, #1333) pelo propósito do
#   tipo, com a regra de categoria do tipo no pedido (`Redator`; o prompt da tela de Modelos não muda), e o `Garantir` cria na Meta
#   (conferência de formato, lista da caixa e perfil com o dono `fora_da_janela` e o mapa de campos). Recusado pela
#   Meta: a próxima versão (`_v2`, `_v3`), contando à IA o motivo. Pausado ou desativado: nada é criado com o nome do
#   tipo (a Meta pausa por qualidade); só ESTE modelo fica bloqueado, e o planejador ainda pode achar outro aprovado e
#   compatível na caixa.
#
# `ler` não paga nada (só a lista e os perfis guardados). `criar` paga a IA e fala com a Meta: só de job, com trava por
# (caixa, tipo) no Redis para dois pré-voos ao mesmo tempo não escreverem dois modelos, e só com a autorização do dono
# (1ª marca; para tipo MARKETING também a 2ª), conferida antes da IA. Cada tentativa conta no teto por hora da WABA
# ANTES da IA (`Limites.reservar!`), e a criação que falha (IA, formato, Meta) fica guardada por `ESPERA_DEPOIS_DA_FALHA`
# por (caixa, tipo): sem isso, cada pré-voo pagaria o redator e gastaria o teto da WABA de novo.
#
# Resposta no formato do `Garantir`, mais `texto` (o corpo com {{1}}), `campos` e, para os tipos da IA, `versao`:
#   { status: :pronto | :em_analise | :indisponivel | :ausente, nome:, idioma:, categoria:, campos:, texto:, versao:, motivo: }
class Whatsapp::Templates::EnvioForaDaJanela::ModeloDoTipo
  Tipos = Whatsapp::Templates::EnvioForaDaJanela::Tipos
  Limites = Whatsapp::Templates::EnvioForaDaJanela::Limites
  Garantir = Whatsapp::Templates::Garantir
  MAX_VERSOES = 3
  # Pior caso medido no código dentro da trava: redator 25 s x 2 tentativas (50 s) + `MetaClient#create` com 3
  # tentativas de consulta, envio e nova consulta a 10 s cada (90 s, mais 1,5 s de pausas) = ~2,5 min. 5 min = 2x margem.
  TRAVA = 5.minutes.to_i
  ESPERA_DEPOIS_DA_FALHA = 30.minutes.to_i

  def self.chave_da_trava(inbox, tipo)
    "whatsapp_fora_da_janela:criando:#{inbox.id}:#{tipo.chave}"
  end

  def self.chave_da_falha(inbox, tipo)
    "whatsapp_fora_da_janela:falha_ia:#{inbox.id}:#{tipo.chave}"
  end

  def initialize(inbox:, tipo:, com_valor: false)
    @inbox = inbox
    @tipo = tipo
    @com_valor = com_valor ? true : false
  end

  def ler
    @tipo.cobranca? ? ler_cobranca : ler_da_ia
  end

  # Os nomes deste tipo nesta caixa (todas as versões): o "compatível" não julga o próprio modelo do tipo.
  def nomes_proprios
    return [pronto_da_cobranca.nome] if @tipo.cobranca?

    (1..MAX_VERSOES).map { |versao| nome(versao) }
  end

  def criar
    token = SecureRandom.hex(8)
    chave = self.class.chave_da_trava(@inbox, @tipo)
    return { status: :em_analise, nome: nome_em_criacao } unless Redis::Alfred.set(chave, token, nx: true, ex: TRAVA)

    begin
      criar_com_trava
    ensure
      Redis::Alfred.delete_if_equals(chave, token)
    end
  end

  private

  # Relê dentro da trava: outro job pode ter acabado de criar.
  def criar_com_trava
    atual = ler
    return atual unless atual[:status] == :ausente

    impedimento = sem_autorizacao || Limites.motivo(@inbox) || falha_recente
    return indisponivel(impedimento) if impedimento
    return indisponivel('limite_por_hora') unless Limites.reservar!(@inbox)

    criar_de_fato(atual)
  end

  def criar_de_fato(atual)
    resultado = @tipo.cobranca? ? garantir_cobranca(criar: true) : criar_com_ia(atual[:versao], atual[:recusa])
    resultado[:status] == :indisponivel ? falhou(resultado[:motivo]) : resultado
  end

  def sem_autorizacao
    return 'sem_consentimento' unless WhatsappTemplateConsent.ativo?(@inbox.account, :utility)

    'sem_consentimento_propaganda' if @tipo.propaganda? && !WhatsappTemplateConsent.ativo?(@inbox.account, :marketing)
  end

  def falha_recente
    Redis::Alfred.get(self.class.chave_da_falha(@inbox, @tipo)).presence
  end

  def ler_cobranca
    resultado = garantir_cobranca(criar: false)
    resultado[:motivo] == 'ausente' ? { status: :ausente } : resultado
  end

  def garantir_cobranca(criar:)
    pronto = pronto_da_cobranca
    Garantir.call(inbox: @inbox, finalidade: :cobranca_vencimento, idioma: nil, criar: criar, momento: @tipo.momento,
                  com_valor: @com_valor)
            .merge(texto: pronto.texto, campos: pronto.campos, categoria: pronto.categoria) { |_chave, veio, _padrao| veio }
  end

  def ler_da_ia
    entrada, versao = ultima_versao
    return { status: :ausente, versao: 1 } unless entrada

    situacao = situacao(entrada).merge(versao: versao)
    return situacao unless situacao[:motivo] == 'recusado' && versao < MAX_VERSOES

    { status: :ausente, versao: versao + 1, recusa: entrada['rejected_reason'].presence }
  end

  # A versão mais nova que está na lista da caixa.
  def ultima_versao
    lista = Whatsapp::Templates::ChannelList.entries(@inbox.channel.class.where(id: @inbox.channel.id).pick(:message_templates))
    MAX_VERSOES.downto(1).each do |versao|
      entrada = lista.find { |item| item['name'] == nome(versao) && item['language'].to_s.casecmp?(Whatsapp::Templates::Finalidades::IDIOMA) }
      return [entrada, versao] if entrada
    end
    nil
  end

  def situacao(entrada)
    status = entrada['status'].to_s.upcase
    return aprovado(entrada) if status == Garantir::APROVADO
    return { status: :em_analise, nome: entrada['name'], idioma: entrada['language'] } if Garantir::EM_ANALISE.include?(status)

    indisponivel(Garantir::INDISPONIVEIS.fetch(status, 'situacao_desconhecida'))
  end

  # O texto é o que está na Meta; o mapa de campos, o do perfil que o `Garantir` gravou ao criar.
  def aprovado(entrada)
    return indisponivel('formato') unless Whatsapp::Templates::SendableFormat.sendable?(entrada)

    texto = Whatsapp::Templates::SendableFormat.hashes(entrada['components']).find { |item| item['type'].to_s.casecmp?('BODY') }
    texto = texto&.dig('text').to_s
    campos = campos_do_perfil(entrada, texto)
    return indisponivel('sem_campos') if campos.nil?

    { status: :pronto, nome: entrada['name'], idioma: entrada['language'],
      categoria: entrada['category'].to_s.upcase.presence || @tipo.categoria, campos: campos, texto: texto }
  end

  def campos_do_perfil(entrada, texto)
    perfil = WhatsappTemplateProfile.for_inbox(@inbox).find_by(name: entrada['name'], language: entrada['language'])
    posicoes = Ai::Redacao::Chaves.extrair(texto).uniq
    campos = perfil&.fields.to_h.slice(*posicoes)
    campos if campos.size == posicoes.size
  end

  def criar_com_ia(versao, recusa)
    escrito = Whatsapp::Templates::EnvioForaDaJanela::Redator.new(inbox: @inbox, tipo: @tipo).escrever(recusa: recusa)
    return indisponivel(escrito) if escrito.is_a?(String)

    texto, campos = escrito
    pronto = Whatsapp::Templates::Finalidades::Pronto.new(
      finalidade: @tipo.chave, nome: nome(versao), nome_amigavel: @tipo.amigavel, dono: Tipos::DONO,
      idioma: Whatsapp::Templates::Finalidades::IDIOMA, texto: texto, campos: campos, botoes: [], categoria: @tipo.categoria
    )
    resultado = Garantir.new(inbox: @inbox, pronto: pronto, idioma: nil).call
    return resultado if resultado[:status] == :indisponivel

    resultado.merge(texto: texto, campos: campos, categoria: @tipo.categoria, versao: versao) { |_chave, veio, _padrao| veio }
  end

  # A criação que falhou (IA, formato, Meta) vale por `ESPERA_DEPOIS_DA_FALHA`: o próximo pré-voo do mesmo (caixa, tipo)
  # não paga a IA nem gasta o teto por hora de novo.
  def falhou(motivo)
    Redis::Alfred.set(self.class.chave_da_falha(@inbox, @tipo), motivo, ex: ESPERA_DEPOIS_DA_FALHA)
    indisponivel(motivo)
  end

  def nome(versao)
    Tipos.nome(@inbox, @tipo, versao)
  end

  # O nome que outro job está criando agora (a trava estava com ele): o que a lista já mostra ou a próxima versão.
  def nome_em_criacao
    return pronto_da_cobranca.nome if @tipo.cobranca?

    atual = ler
    atual[:nome].presence || nome(atual[:versao] || 1)
  end

  def pronto_da_cobranca
    Whatsapp::Templates::Finalidades.pronto(:cobranca_vencimento, momento: @tipo.momento, com_valor: @com_valor)
  end

  def indisponivel(motivo)
    { status: :indisponivel, motivo: motivo }
  end
end
