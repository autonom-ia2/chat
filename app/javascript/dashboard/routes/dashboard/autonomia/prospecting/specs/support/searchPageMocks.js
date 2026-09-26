// Fábricas dos módulos de rede da tela de busca. Ficam fora do harness porque o
// vi.mock de cada spec importa este arquivo antes da página existir.
export const prospectingApiMock = () => ({
  default: {
    getSettings: vi.fn(),
    getSearches: vi.fn(),
    getSearch: vi.fn(),
    getLocationSuggestions: vi.fn(),
    getLocationDetails: vi.fn(),
    createSearch: vi.fn(),
    updateSearch: vi.fn(),
    deleteSearch: vi.fn(),
    createCrmCards: vi.fn(),
    addLeadsToCampaign: vi.fn(),
    adoptOwner: vi.fn(),
    verifyLeadWhatsApp: vi.fn(),
    enrichLead: vi.fn(),
    researchLead: vi.fn(),
    exportSearch: vi.fn(),
    discardLeads: vi.fn(),
    createLeadContacts: vi.fn(),
    updateLead: vi.fn(),
    refuseLeadConsent: vi.fn(),
    withdrawLeadConsentRefusal: vi.fn(),
    createSavedPreset: vi.fn(),
  },
});

export const crmKanbanApiMock = () => ({
  default: {
    getPipelines: vi.fn(),
    getStages: vi.fn(),
  },
});
