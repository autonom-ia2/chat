require 'rails_helper'

# Kit do desenvolvedor do link de site (CA-1.6, #1068): página pública com o código pronto do botão.
RSpec.describe 'Public tracked link kit', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+5511933779463', sync_templates: false, validate_provider_config: false)
  end
  let(:tracked_link) do
    Ctwa::TrackedLink.create!(account: account, inbox: channel.inbox, name: 'LP Seguro Viagem', usage: 'website',
                              prefilled_text: 'Quero cotar "seguro" </script>', allowed_origins: ['https://placement.com.br'])
  end

  it 'mostra o código pronto com o endereço de aviso, o número e a mensagem, sem indexar' do
    with_modified_env FRONTEND_URL: 'https://chat.hub2you.ai' do
      get "/l/#{tracked_link.code}/kit"
    end

    expect(response).to have_http_status(:ok)
    expect(response.headers['X-Robots-Tag']).to eq('noindex, nofollow')
    expect(response.body).to include(
      'Ligar o botão do WhatsApp da página LP Seguro Viagem', 'https://placement.com.br', 'data-chat2you-whatsapp',
      CGI.escapeHTML(%("https://chat.hub2you.ai/l/#{tracked_link.code}/clicks")),
      CGI.escapeHTML('"https://wa.me/5511933779463?text="'),
      CGI.escapeHTML(Ctwa::TrackedLink::CODE_ALPHABET.join.to_json)
    )
  end

  it 'não deixa o texto da mensagem fechar o script do site' do
    get "/l/#{tracked_link.code}/kit"

    expect(response.body).not_to include('</script>"')
    message = 'Quero cotar "seguro" </script>'.to_json
    expect(message).to include('\\u003c/script\\u003e')
    expect(response.body).to include("var MESSAGE = #{CGI.escapeHTML(message)};")
  end

  it 'não existe para link que não é de site nem para código desconhecido' do
    direct = Ctwa::TrackedLink.create!(account: account, inbox: channel.inbox, name: 'Balcão', usage: 'direct')

    get "/l/#{direct.code}/kit"
    expect(response).to have_http_status(:not_found)

    get '/l/ZZZZZZ/kit'
    expect(response).to have_http_status(:not_found)
  end
end
