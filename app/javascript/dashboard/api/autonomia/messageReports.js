import ApiClient from '../ApiClient';

// #284 — attendant feedback ("wrong reply") on a message posted by an Autonomia
// agent. Open to any agent of the account (not admin-only like the agents area).
class AutonomiaMessageReportsAPI extends ApiClient {
  constructor() {
    super('autonomia/agents/message_reports', { accountScoped: true });
  }
}

export default new AutonomiaMessageReportsAPI();
