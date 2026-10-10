import { useEmailEditor } from '../composables/useEmailEditor';

// #1093 (defense in depth): replacing the selection's content with text is only for a text or a
// button. With a section or column selected it would swap the whole structure for loose text.
describe('useEmailEditor — setSelectedText', () => {
  const fake = type => ({
    get: key => (key === 'type' ? type : null),
    components: vi.fn(),
  });
  const { selectedComponent, setSelectedText, isTextSelected } =
    useEmailEditor();

  afterEach(() => {
    selectedComponent.value = null;
  });

  it.each(['mj-section', 'mj-column', 'mj-wrapper', 'mj-image'])(
    'never replaces a %s',
    type => {
      const component = fake(type);
      selectedComponent.value = component;

      expect(isTextSelected.value).toBe(false);
      expect(setSelectedText('Texto novo')).toBe(false);
      expect(component.components).not.toHaveBeenCalled();
    }
  );

  it.each(['mj-text', 'mj-button'])('replaces the content of a %s', type => {
    const component = fake(type);
    selectedComponent.value = component;

    expect(isTextSelected.value).toBe(true);
    expect(setSelectedText('Texto novo')).toBe(true);
    expect(component.components).toHaveBeenCalledWith('Texto novo');
  });
});
