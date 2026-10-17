import { mount } from '@vue/test-utils';
import { defineComponent, nextTick, reactive, ref } from 'vue';
import { usePainelDoContatoRecolhido } from '../fork/usePainelDoContatoRecolhido';

// Painel do contato recolhido ao entrar numa conversa (#1781): no carregamento (também quando as preferências
// chegam depois), ao trocar de conversa e ao sair e voltar. Depois que a pessoa abre, ninguém fecha.
const montar = ({
  params = { conversation_id: '7' },
  aberto = true,
  pronto = true,
} = {}) => {
  const route = reactive({
    name: 'inbox_conversation',
    params,
    fullPath: `/conversations/${params.conversation_id}`,
    hash: '',
  });
  const uiSettings = ref(pronto ? { is_contact_sidebar_open: aberto } : {});
  const carregado = ref(pronto);
  const updateUISettings = vi.fn(novo => {
    uiSettings.value = { ...uiSettings.value, ...novo };
  });
  mount(
    defineComponent({
      setup() {
        usePainelDoContatoRecolhido({
          route,
          uiSettings,
          updateUISettings,
          carregado,
        });
        return () => null;
      },
    })
  );
  return { route, uiSettings, carregado, updateUISettings };
};

describe('usePainelDoContatoRecolhido', () => {
  it('entrar na conversa (inclusive no carregamento) recolhe o painel aberto', () => {
    const { uiSettings, updateUISettings } = montar();
    expect(updateUISettings).toHaveBeenCalledWith({
      is_contact_sidebar_open: false,
    });
    expect(uiSettings.value.is_contact_sidebar_open).toBe(false);
  });

  it('preferências ainda não carregadas: recolhe quando chegam', async () => {
    const { uiSettings, carregado, updateUISettings } = montar({
      pronto: false,
    });
    expect(updateUISettings).not.toHaveBeenCalled();
    uiSettings.value = { is_contact_sidebar_open: true };
    carregado.value = true;
    await nextTick();
    expect(updateUISettings).toHaveBeenCalledTimes(1);
    expect(uiSettings.value.is_contact_sidebar_open).toBe(false);
  });

  it('já recolhido: não grava nada', () => {
    const { updateUISettings } = montar({ aberto: false });
    expect(updateUISettings).not.toHaveBeenCalled();
  });

  it('depois que a pessoa abre, ninguém fecha, nem com filtro ou âncora nova; trocar de conversa recolhe', async () => {
    const { route, uiSettings, updateUISettings } = montar();
    expect(updateUISettings).toHaveBeenCalledTimes(1);
    uiSettings.value = { is_contact_sidebar_open: true };
    await nextTick();
    route.fullPath = '/conversations/7?aba=notas#mensagem-3';
    route.hash = '#mensagem-3';
    route.params = { conversation_id: '7' };
    await nextTick();
    expect(updateUISettings).toHaveBeenCalledTimes(1);
    expect(uiSettings.value.is_contact_sidebar_open).toBe(true);

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
