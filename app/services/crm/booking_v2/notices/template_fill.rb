# Os valores do modelo v2 do aviso (#1524): a decisão do `Notices::Route` traz os `campos` do corpo e os `botoes` do
# `Garantir`; aqui eles viram o `processed_params` que o envio do upstream espera, preenchidos pelo catálogo de campos
# (`TemplateFields::Resolver.for_meeting`).
#
#   Crm::BookingV2::Notices::TemplateFill.new(decision, meeting: meeting, invite: invite).call
#   # => { body: { '1' => 'Ana', '2' => '14/10 às 15:00' },
#   #      buttons: [{ 'type' => 'url', 'parameter' => 'AB3K9QXZ' }, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }] }
#
# `buttons` alinhado pelo `indice` de cada botão no modelo (posição sem nada a mandar = nil): o URL leva o valor do
# `campo` (o fim variável do endereço), a resposta rápida só o `payload` (sem `parameter`, o `SendComponents` monta o
# botão com o payload estável). Sem botões, `buttons: nil`.
class Crm::BookingV2::Notices::TemplateFill
  def initialize(decision, meeting:, invite:)
    @campos = decision.campos.to_h
    @botoes = Array(decision.botoes)
    @meeting = meeting
    @invite = invite
  end

  def call
    { body: @campos.to_h { |numero, campo| [numero.to_s, resolver.value(campo).to_s] }, buttons: buttons }
  end

  private

  def buttons
    return if @botoes.empty?

    por_indice = @botoes.index_by { |botao| botao['indice'].to_i }
    (0..por_indice.keys.max).map { |indice| button(por_indice[indice]) }
  end

  def button(botao)
    case botao&.dig('tipo')
    when 'url' then { 'type' => 'url', 'parameter' => resolver.value(botao['campo']).to_s }
    when 'quick_reply' then { 'type' => 'quick_reply', 'payload' => botao['payload'] }
    end
  end

  def resolver
    @resolver ||= TemplateFields::Resolver.for_meeting(@meeting, invite: @invite, requested_keys: requested_keys)
  end

  def requested_keys
    @campos.values + @botoes.filter_map { |botao| botao['campo'] }
  end
end
