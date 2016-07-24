
require "yaml"

alias UIComponent = UI::Control* | Nil

module CUI extend self
  class Exception < Exception
  end

  enum MenuDesc
    Enabled     = 2<<0
    Check       = 2<<1
    Quit        = 2<<2
    Preferences = 2<<3
    About       = 2<<4
    Separator   = 2<<5
  end

  def init: Boolean
    o = UI::InitOptions.new
    err = UI.init pointerof(o)
    if !uiNil?(err)
      return false
    end
    true
  end

  private def idx_component(name : String, component : UI::Control*)
    @@compIdx ||= Hash(String, UI::Control*).new
    @@compIdx.not_nil![name] = component
  end

  def get(name : String) : UI::Control* | Nil
    return nil if @@compIdx.nil?
    compIdx = @@compIdx.not_nil!
    return compIdx[name] if compIdx.has_key?(name)
    nil
  end

  def get!(name : String) : UI::Control*
    m = get name
    raise CUI::Exception.new "Not found: #{name}" if m.is_a?(Nil)
    m
  end

  def get_as_menuitem(name : String) : UI::MenuItem* | Nil
    m = get name
    return nil if m.is_a?(Nil)
    m as UI::MenuItem*
  end

  def get_as_menuitem!(name : String) : UI::MenuItem*
    (get! name) as UI::MenuItem*
  end

  def get_mainwindow : UI::Window* | Nil
    m = get "sys::mainwindow"
    return nil if m.is_a?(Nil)
    m as UI::Window*
  end

  def get_mainwindow! : UI::Window*
    (get! "sys::mainwindow") as UI::Window*
  end

  # ----------------------------------------------------------------------------
  # Create and add components: windows, dialogs, etc.
  # ----------------------------------------------------------------------------

  # Window logic is as follow:
  # First window met becomes main -- later on we may override using 'main' or what not
  private def spawn_component(type, name, text, attributes) : UIComponent
    component = nil
    case type
    when "window"
      attributes["width"] ||= "640"
      attributes["height"] ||= "480"
      attributes["hasMenubar"] ||= "0"
      component = ui_control UI.new_window text.to_s, attributes["width"].to_i, attributes["height"].to_i, attributes["hasMenubar"].to_i

      idx_component "sys::mainwindow", component if !get "sys::mainwindow"

    when "vertical_box"
      raw_component = UI.new_vertical_box
      UI.box_set_padded raw_component, attributes["padded"].to_i if attributes.has_key?("padded")
      component = ui_control raw_component
    when "horizontal_box"
      raw_component = UI.new_horizontal_box
      UI.box_set_padded raw_component, attributes["padded"].to_i if attributes.has_key?("padded")
      component = ui_control raw_component
    when "horizontal_separator"
      ui_control UI.new_horizontal_separator
    when "group"
      raw_component = UI.new_group text.to_s
      UI.group_set_margined raw_component, attributes["margined"].to_i if attributes.has_key?("margined")
      component = ui_control raw_component
    when "button"
      raw_component = UI.new_button text.to_s
      component = ui_control raw_component
    when "font_button"
      raw_component = UI.new_font_button
      component = ui_control raw_component
    when "color_button"
      raw_component = UI.new_color_button
      component = ui_control raw_component
    when "checkbox"
      raw_component = UI.new_checkbox text.to_s
      component = ui_control raw_component
    when "entry"
      raw_component = UI.new_entry
      UI.entry_set_text raw_component, text.to_s
      component = ui_control raw_component
    when "label"
      raw_component = UI.new_label text.to_s
      component = ui_control raw_component
    when "date_picker"
      raw_component = UI.new_date_picker
      component = ui_control raw_component
    when "time_picker"
      raw_component = UI.new_time_picker
      component = ui_control raw_component
    when "date_time_picker"
      raw_component = UI.new_date_time_picker
      component = ui_control raw_component
    when "slider"
      st, en = text.to_s.split(",").map{ |v| v.strip.to_i }
      raw_component = UI.new_slider st, en
    end

    idx_component name.to_s, component if !name.nil? && !component.is_a?(Nil)

    component
  end

  private def add_child(type, parent : UI::Control*, child)
    case type
    when "window"
      UI.window_set_child parent as UI::Window*, child
    when "vertical_box", "horizontal_box"
      # TODO stretchy instead of 0
      UI.box_append parent as UI::Box*, child, 0
    when "group"
      UI.group_set_child parent as UI::Group*, child
    end
  end

  private def inflate_component(ydesc : YAML::Any) : UIComponent
    component_type = nil
    component_text = nil
    component_name = nil
    attributes = {} of String => String
    children = nil
    ydesc.each do |desc, data|
      #puts desc
      #puts data
      case desc
      when "children"
        children = inflate_components data
      when "name"
        component_name = data
      else
        if component_type.nil?
          component_type = desc
          component_text = data
        else
          attributes[desc.to_s] = data.to_s
        end
      end
    end
    # So now we should now what we need to know about our component_text
    # TODO check legit
    component = spawn_component component_type, component_name, component_text, attributes
    unless component.is_a?(Nil)
      unless children.nil?
        children.each do |child|
          add_child component_type, component, child
        end
      end
    end
    component
    #puts "Component type=#{component_type} name=#{component_name} text=#{component_text}"
    #puts attributes
  end

  private def inflate_components(ydesc : YAML::Any)
    components = [] of UI::Control*
    ydesc.each do |desc|
      component = inflate_component desc
      components << component unless component.is_a?(Nil)
    end
    components
  end

  # Public API

  def inflate(file_name : String)
    components = [] of UI::Control*
    ydesc = YAML.parse File.read file_name
    ydesc.each do |desc, data|
      case desc
      when "windows"
        components = inflate_components data
      when "components"
        components = inflate_components data
      end
    end
    components
  end

  # ----------------------------------------------------------------------------
  # Create menubar and specialized items such as quit, preferences...
  # ----------------------------------------------------------------------------

  private def inflate_menuitems(ydesc : YAML::Any)
    components = [] of Array(String | Int32 | Nil)
    ydesc.each do |item|
      component_name = nil
      component_desc = MenuDesc::Enabled.value
      component_text = nil
      item.each do |desc, data|
        case desc
        when "name"
          component_name = data.to_s
        when "type"
          case data
          when "check"
            component_desc |= MenuDesc::Check.value
          when "quit"
            component_name = "sys#quit"
            component_desc |= MenuDesc::Quit.value
          when "preferences"
            component_name = "sys#preferences"
            component_desc |= MenuDesc::Preferences.value
          when "about"
            component_name = "sys#about"
            component_desc |= MenuDesc::About.value
          when "separator"
            component_name = "sys#separator"
            component_desc |= MenuDesc::Separator.value
          end
        when "enabled"
          component_desc &= ~MenuDesc::Enabled.value if data.to_s.strip != "true"
        when "item"
          component_text = data.to_s
        end
      end
      raise CUI::Exception.new "Missing menu item information: #{component_name} -> #{component_text}" if component_name.nil? || component_text.nil?
      components << [component_name, component_text, component_desc]
    end
    components
  end

  private def inflate_menu(ydesc : YAML::Any)
    menu = nil
    children = nil
    ydesc.each do |desc, data|
      case desc
      when "items"
        children = inflate_menuitems data
      when "menu"
        menu = UI.new_menu data.to_s
      end
    end
    unless menu.is_a?(Nil)
      unless children.nil?
        children.each do |child|
          name = child[0] as String
          text = child[1] as String
          desc = child[2] as Int32
          if (desc & MenuDesc::Check.value != 0)
            item = UI.menu_append_check_item menu, text
          elsif (desc & MenuDesc::Quit.value != 0)
            item = UI.menu_append_quit_item menu
          elsif (desc & MenuDesc::Preferences.value != 0)
            item = UI.menu_append_preferences_item menu
          elsif (desc & MenuDesc::About.value != 0)
            item = UI.menu_append_about_item menu
          elsif (desc & MenuDesc::Separator.value != 0)
            UI.menu_append_separator menu
          else
            item = UI.menu_append_item menu, text
          end
          UI.menu_item_disable item if (desc & MenuDesc::Enabled.value == 0)

          idx_component name, ui_control item unless item.is_a?(Nil)
        end
      end
    end
  end

  private def inflate_menubar(ydesc : YAML::Any)
    ydesc.each do |desc|
      inflate_menu desc
    end
  end

  # Public API

  def menubar(file_name : String)
    ydesc = YAML.parse File.read file_name
    ydesc.each do |desc, data|
      case desc
      when "menubar"
        inflate_menubar data
      end
    end
  end

  # ----------------------------------------------------------------------------
  # Playground: Currently Unused.
  # ----------------------------------------------------------------------------

  class Menu
    def init(text : String)
      @menu = UI.newMenu text
    end

    def append(name : String)
      UI.menuAppendItem @menu, name
    end
  end
end