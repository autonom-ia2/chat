import { createPinia, setActivePinia } from 'pinia';
import { useCallsStore } from 'dashboard/stores/calls';
import { syncConversationCallVisibility } from '../voice';

vi.mock('dashboard/api/channel/voice/twilioVoiceClient', () => ({
  default: { endClientCall: vi.fn() },
}));
vi.mock('dashboard/composables/useWhatsappCallSession', () => ({
  cleanupWhatsappSession: vi.fn(),
  isLocalWhatsappCall: vi.fn(() => false),
}));

// #2249: chamada recebida some só quando OUTRA PESSOA pega a conversa; robô não é "outro agente".
// Upgrade 4.20.1 (#3120): com o roteamento de chamadas do upstream (#16469, #16637), a chamada
// recebida só sai quando o agente também perde o acesso à conversa (`semAcesso`).
const semAcesso = () => false;
describe('syncConversationCallVisibility com robô responsável', () => {
  const chamada = {
    callSid: 'CA1',
    conversationId: 10,
    callDirection: 'inbound',
  };

  beforeEach(() => {
    setActivePinia(createPinia());
    useCallsStore().addCall(chamada);
  });

  it('mantém a chamada quando quem cuida é um robô', () => {
    syncConversationCallVisibility(
      { id: 10, meta: { assignee: { id: 7 }, assignee_type: 'AgentBot' } },
      5,
      semAcesso
    );
    expect(useCallsStore().calls).toHaveLength(1);
  });

  it('tira a chamada quando outra pessoa pega a conversa', () => {
    syncConversationCallVisibility(
      { id: 10, meta: { assignee: { id: 7 }, assignee_type: 'User' } },
      5,
      semAcesso
    );
    expect(useCallsStore().calls).toHaveLength(0);
  });
});
