require 'rails_helper'
require_relative '../rich_native_context'

# chat#1709 (demo integrada): no plano B do Híbrido, cada mensagem sai num job próprio e o "digitando…" dorme um tempo
# proporcional ao texto. Duas mensagens seguidas de tipos diferentes (lista e localização) saíam fora de ordem.
describe WhatsappHybrid::RichNative::SendOrder do
  include_context 'with a hybrid inbox for rich native'

  let(:sent) { [] }

  before do
    allow(client).to receive(:send_list) do
      sent << :list
      { 'id' => 'true_5511937016094@c.us_3EB0LIST' }
    end
    allow(client).to receive(:send_location) do
      sent << :location
      {}
    end
  end

  def two_messages
    list = outgoing(options)
    location = outgoing({ type: 'location', latitude: -23.5489, longitude: -46.6388, name: 'Unidade Centro' }, content: '')
    [list, location]
  end

  it 'sends in the order the attendant sent, even when the newer job runs first' do
    flag_on!
    list, location = two_messages
    busy = false
    # A localização (job mais novo) roda primeiro e espera a vez; enquanto espera, o job da lista roda. Sem o
    # "digitando…", a única espera é a da vez (sem ela, a localização sairia sozinha e primeiro).
    allow(Kernel).to receive(:sleep) do
      next if busy

      busy = true
      send_by_web(list.reload)
    end

    with_modified_env(WHATSAPP_HYBRID_TYPING: 'false') { send_by_web(location) }

    expect(sent).to eq(%i[list location])
    expect(Redis::Alfred.get("whatsapp_hybrid:send_order:#{conversation.id}")).to be_nil
  end

  it 'does not wait when nothing older is pending' do
    flag_on!
    list, location = two_messages
    send_by_web(list)

    expect(described_class.older_pending?(location.reload)).to be(false)
    send_by_web(location)

    expect(sent).to eq(%i[list location])
  end

  it 'stops waiting after MAX_WAIT for an older message that never leaves' do
    flag_on!
    _list, location = two_messages
    clock = 0.0
    allow(described_class).to receive(:monotonic) { clock += 1 }

    send_by_web(location)

    expect(sent).to eq(%i[location])
  end

  it 'keeps main without the flag (no wait, no lock)' do
    _list, location = two_messages
    allow(described_class).to receive(:in_turn)

    send_by_web(location)

    expect(described_class).not_to have_received(:in_turn)
  end
end
