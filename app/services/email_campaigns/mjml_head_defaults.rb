# Head defaults (<mj-attributes>) resolved into the body elements (#1074) — Ruby twin of the
# editor's mjmlHeadDefaults.js; both must produce the same attributes in the same order.
#
# grapesjs-mjml has no component for <mj-attributes>: its children render as visible blocks and the
# defaults never reach the canvas. Writing them on each body element keeps canvas and sent e-mail
# identical, so <mj-attributes> can be dropped. Precedence follows mjml-core: explicit > mj-class
# children of an ancestor's class > mj-class > tag default > mj-all. Only attributes the tag
# accepts are written, per mjmlAllowedAttributes.json (generated from the mjml-browser bundle the
# editor compiles with: scripts/mjml-attributes/build.mjs).
class EmailCampaigns::MjmlHeadDefaults
  TABLE = Rails.root.join('app/javascript/dashboard/components-next/Campaigns/Pages/CampaignPage/EmailCampaign/builder/' \
                          'mjmlAllowedAttributes.json')
  ALLOWED = JSON.parse(TABLE.read).fetch('components').transform_values(&:to_set).freeze
  # mjml-core accepts css-class on every component.
  GLOBAL_ATTRIBUTES = %w[css-class].freeze

  def self.collect(attributes_elements)
    attributes_elements.each_with_object(new) { |element, defaults| defaults.add_block(element) }
  end

  def initialize
    @all = {}
    @by_tag = {}
    @classes = {}
    @classes_default = {}
  end

  def add_block(attributes_element)
    if corrupted?(attributes_element)
      attributes_element.css('*').each { |element| add_default(element) }
    else
      attributes_element.element_children.each do |child|
        add_default(child)
        add_class_children(child) if child.name == 'mj-class'
      end
    end
  end

  # Attributes to write on a body element: its own (minus mj-class) plus the defaults it inherits.
  def resolve(element, inherited_classes)
    own = attributes_of(element)
    own_classes = own.delete('mj-class')
    tag = element.name
    return own unless ALLOWED.key?(tag)

    inherited = @all.merge(@by_tag.fetch(tag, {}))
                    .merge(class_attributes(class_names(own_classes)))
                    .merge(class_child_attributes(class_names(inherited_classes), tag))
    added = inherited.reject { |attr, _| own.key?(attr) || !accepts?(tag, attr) }
    own.merge(added)
  end

  private

  def attributes_of(element)
    element.attribute_nodes.to_h { |attr| [attr.name, attr.value] }
  end

  # Saved by the old editor: defaults nested inside each other (a self-closed tag read as open).
  # mj-all / tag defaults never have children, so any of them with children means corruption.
  def corrupted?(attributes_element)
    attributes_element.element_children.any? { |child| child.name != 'mj-class' && child.element_children.any? }
  end

  def add_default(element)
    attrs = attributes_of(element)
    case element.name
    when 'mj-all' then @all = @all.merge(attrs)
    when 'mj-class'
      name = attrs.delete('name')
      @classes[name] = @classes.fetch(name, {}).merge(attrs) if name
    else @by_tag[element.name] = @by_tag.fetch(element.name, {}).merge(attrs)
    end
  end

  # <mj-class name="x"><mj-text .../></mj-class>: defaults for mj-text inside an element of class x.
  def add_class_children(class_element)
    name = class_element['name']
    return if name.nil?

    class_element.element_children.each do |child|
      by_tag = @classes_default.fetch(name, {})
      @classes_default[name] = by_tag.merge(child.name => by_tag.fetch(child.name, {}).merge(attributes_of(child)))
    end
  end

  def class_names(value)
    value.to_s.split
  end

  # mjml-core: later classes win, but css-class values are concatenated.
  def class_attributes(names)
    names.reduce({}) do |acc, name|
      attrs = @classes.fetch(name, {})
      css = acc['css-class'] && attrs['css-class'] ? { 'css-class' => "#{acc['css-class']} #{attrs['css-class']}" } : {}
      acc.merge(attrs).merge(css)
    end
  end

  def class_child_attributes(names, tag)
    names.reduce({}) { |acc, name| acc.merge(@classes_default.fetch(name, {}).fetch(tag, {})) }
  end

  def accepts?(tag, attr)
    ALLOWED[tag].include?(attr) || GLOBAL_ATTRIBUTES.include?(attr)
  end
end
