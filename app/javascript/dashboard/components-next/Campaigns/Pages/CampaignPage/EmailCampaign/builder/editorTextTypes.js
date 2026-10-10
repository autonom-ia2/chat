// The e-mail blocks whose content is text the person wrote (#1093): only these can be rewritten
// by "Melhorar com IA" or receive a personalization field. A section, column or image is
// structure; replacing its content with text would lose the blocks inside it.
export const TEXT_COMPONENT_TYPES = ['mj-text', 'mj-button'];

export const isTextComponentType = type => TEXT_COMPONENT_TYPES.includes(type);
