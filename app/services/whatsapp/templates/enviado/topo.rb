# O topo do modelo comum na foto do envio (#1717): texto, foto, vídeo ou documento. O topo de produto (SPM) não passa
# aqui: vai em `produto`. O topo dos cartões do carrossel vai em `cartoes`.
#
# Texto: `{ tipo: 'text', texto }`, com os valores enviados (com campo que ficou sem valor, texto nil; nunca "{{1}}").
# Mídia: `{ tipo: 'image'|'video'|'document', url, nome }`. A `url` só existe quando o arquivo é NOSSO (ActiveStorage,
# desta conta), com a mesma regra dos cartões: o que o disparo marcou (`media_signed_id`, `HeaderMedia.dispatch_file`)
# ou o escolhido na campanha (`media_blob`); só ao reler a campanha, sem link nem referência, o aprovado no perfil do
# modelo. Link digitado, link assinado e link da Meta viram nil: a tela mostra o ícone do tipo. `nome` é o nome do
# arquivo do documento (o nosso ou o que o envio levou à Meta); nil nos outros tipos. A `url` é o rails_blob_url
# permanente, o mesmo padrão dos anexos da conversa (dado do chat é do negócio). Envio sem topo de mídia: sem `topo`.
module Whatsapp::Templates::Enviado::Topo
  # A Meta aceita até 60 caracteres no topo de texto; nome de arquivo cabe em 255.
  TEXTO_MAX = 60
  NOME_MAX = 255
  SendParams = Whatsapp::Templates::SendParams

  module_function

  def de(template, processed, inbox, perfil: false)
    topo = SendParams.as_hash(processed['header'])
    return texto(template, topo) if SendParams.component(template, 'HEADER')&.dig('format').to_s.casecmp?('TEXT')

    tipo = Whatsapp::Templates::HeaderMedia.media_type(template)
    # Envio sem topo (conversa): sem `topo`. Só a campanha relida usa o arquivo do perfil.
    return if tipo.nil? || (topo.empty? && !perfil)

    midia(tipo, topo, inbox, template, perfil)
  end

  def texto(template, valores)
    modelo = SendParams.component(template, 'HEADER')['text'].to_s
    valores = valores.transform_keys(&:to_s).reject { |_chave, valor| valor.to_s.strip.empty? }
    texto = CampaignJourney::TemplatePlaceholders.render(modelo, valores).strip
    { 'tipo' => 'text', 'texto' => (texto.first(TEXTO_MAX).presence unless texto.include?(CampaignJourney::TemplatePlaceholders::OPEN)) }
  end

  def midia(tipo, topo, inbox, template, perfil)
    blob = arquivo(topo, inbox, template, perfil)
    { 'tipo' => tipo, 'url' => Whatsapp::Templates::Enviado::Cartoes.url_estavel(blob), 'nome' => nome(tipo, topo, blob) }
  end

  # A referência assinada (a do disparo ou a do arquivo escolhido), só se o arquivo é desta conta. Só ao reler a campanha
  # (perfil: true, `SentMessageRecorder`), sem link e sem referência, o arquivo do perfil do modelo, o mesmo do disparo.
  def arquivo(topo, inbox, template, perfil)
    assinado = topo['media_signed_id'].presence || topo['media_blob'].presence
    return Whatsapp::Templates::Enviado::Cartoes.da_conta(ActiveStorage::Blob.find_signed(assinado.to_s), inbox) if assinado
    return if !perfil || topo['media_url'].to_s.strip.present?

    Whatsapp::Templates::HeaderMedia.profile_file(inbox, template)&.blob
  end

  def nome(tipo, topo, blob)
    return unless tipo == 'document'

    (blob&.filename.to_s.presence || topo['media_name'].to_s.strip).first(NOME_MAX).presence
  end
end
