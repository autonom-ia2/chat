import { mount } from '@vue/test-utils';
import { defineComponent, nextTick, reactive, ref } from 'vue';
import { usePainelDoContatoRecolhido } from '../fork/usePainelDoContatoRecolhido';

// Painel do contato recolhido ao entrar numa conversa (#1781): no carregamento, ao trocar de conversa e ao
// sair e voltar. A pessoa abre quando quiser; fora da conversa nada muda.
const montar = ({ params = { conversation_id: '7' }, aberto = true } = {}) => {
  const route = reactive({ name: 'inbox_conversation', params });
  const uiSettings = ref({ is_contact_sidebar_open: aberto });
  const updateUISettings = vi.fn(novo => {
    uiSettings.value = { ...uiSettings.value, ...novo };
  });
  mount(
    defineComponent({
      setup() {
        usePainelDoContatoRecolhido({ route, uiSettings, updateUISettings });
        return () => null;
      },
    })
  );
  return { route, uiSettings, updateUISettings };
};

describe('usePainelDoContatoRecolhido', () => {
  it('entrar na conversa (inclusive no carregamento) recolhe o painel aberto', () => {
    const { uiSettings, updateUISettings } = montar();
    expect(updateUISettings).toHaveBeenCalledWith({
      is_contact_sidebar_open: false,
    });
    expect(uiSettings.value.is_contact_sidebar_open).toBe(false);
  });

  it('já recolhido: não grava nada', () => {
    const { updateUISettings } = montar({ aberto: false });
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('a pessoa abre; trocar de conversa recolhe de novo', async () => {
    const { route, uiSettings, updateUISettings } = montar();
    uiSettings.value = { is_contact_sidebar_open: true };
    await nextTick();
    expect(updateUISettings).toHaveBeenCalledTimes(1);
    route.params = { conversation_id: '8' };
    await nextTick();
    expect(updateUISettings).toHaveBeenCalledTimes(2);
    expect(uiSettings.value.is_contact_sidebar_open).toBe(false);
  });

  it('sair da conversa não mexe; voltar para a mesma recolhe de novo', async () => {
    const { route, uiSettings, updateUISettings } = montar();
    uiSettings.value = { is_contact_sidebar_open: true };
    route.name = 'crm_kanban_index';
    route.params = {};
    await nextTick();
    expect(updateUISettings).toHaveBeenCalledTimes(1);
    expect(uiSettings.value.is_contact_sidebar_open).toBe(true);
    route.name = 'inbox_conversation';
    route.params = { conversation_id: '7' };
    await nextTick();
    expect(updateUISettings).toHaveBeenCalledTimes(2);
    expect(uiSettings.value.is_contact_sidebar_open).toBe(false);
  });

  it('fora da conversa nada muda', () => {
    const { updateUISettings } = montar({ params: {} });
    expect(updateUISettings).not.toHaveBeenCalled();
  });
});
