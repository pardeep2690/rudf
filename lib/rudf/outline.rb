# frozen_string_literal: true

module RUDF
  # Resolves document destinations (named destinations, explicit destinations
  # and GoTo/URI actions) to page indexes, and builds the table of contents.
  #
  # Mixed into {Document}; relies on its +@pdf+ store, its ordered page list
  # and the page-object-number map recorded while flattening the page tree.
  module Outline
    # The document's table of contents, in PyMuPDF's shape.
    #
    # With +simple: true+ (default) each entry is +[level, title, page]+ where
    # +page+ is a 1-based page number (or -1 when it cannot be resolved). With
    # +simple: false+ a fourth element carries a details Hash including the
    # destination kind and target point.
    def get_toc(simple: true)
      ensure_open
      catalog = @pdf.catalog
      return [] unless catalog.is_a?(Hash)

      outlines = @pdf.resolve(catalog["Outlines"])
      return [] unless outlines.is_a?(Hash)

      toc = []
      first = outlines["First"]
      walk_outline(@pdf.resolve(first), 1, toc, simple, {}) if first
      toc
    end
    alias toc get_toc

    # Map a page object reference (or explicit page number) to a 0-based index,
    # or +nil+ when unknown.
    def page_index_for(ref)
      pages # ensure @page_refs is built
      if ref.is_a?(PDF::Reference)
        idx = @page_refs.index(ref.number)
        return idx
      elsif ref.is_a?(Integer)
        return ref if ref.between?(0, @page_refs.length - 1)
      end
      nil
    end

    # Resolve a destination or action into
    # +{kind:, page:, to:, uri:}+ (page is 0-based, or nil).
    def resolve_destination(dest)
      dest = @pdf.resolve(dest)
      case dest
      when PDF::Name then resolve_named_destination(dest.value)
      when String then resolve_named_destination(dest)
      when Array then dest_from_array(dest)
      when Hash then resolve_action(dest)
      else { kind: :none, page: nil, to: nil, uri: nil }
      end
    end

    private

    def walk_outline(node, level, toc, simple, seen)
      while node.is_a?(Hash)
        key = node.object_id
        break if seen[key]

        seen[key] = true

        title = title_of(node)
        info = resolve_outline_target(node)
        page1 = info[:page].nil? ? -1 : info[:page] + 1
        toc << (simple ? [level, title, page1] : [level, title, page1, info])

        child = node["First"]
        walk_outline(@pdf.resolve(child), level + 1, toc, simple, seen) if child

        node = @pdf.resolve(node["Next"])
      end
    end

    def title_of(node)
      title = @pdf.resolve(node["Title"])
      title.is_a?(String) ? decode_text_string(title) : ""
    end

    def resolve_outline_target(node)
      if node.key?("Dest")
        resolve_destination(node["Dest"])
      elsif node.key?("A")
        resolve_action(@pdf.resolve(node["A"]))
      else
        { kind: :none, page: nil, to: nil, uri: nil }
      end
    end

    def resolve_action(action)
      return { kind: :none, page: nil, to: nil, uri: nil } unless action.is_a?(Hash)

      subtype = @pdf.resolve(action["S"])
      name = subtype.is_a?(PDF::Name) ? subtype.value : nil
      case name
      when "GoTo"
        resolve_destination(action["D"])
      when "URI"
        uri = @pdf.resolve(action["URI"])
        { kind: :uri, page: nil, to: nil, uri: uri.is_a?(String) ? uri.b.force_encoding("UTF-8") : nil }
      when "GoToR"
        { kind: :remote, page: nil, to: nil, uri: file_spec(action["F"]) }
      else
        { kind: :none, page: nil, to: nil, uri: nil }
      end
    end

    def dest_from_array(arr)
      page_ref = @pdf.resolve(arr[0])
      idx = page_index_for(arr[0]) || page_index_for(page_ref)
      to = nil
      if arr.length >= 4
        x = numeric(arr[2])
        y = numeric(arr[3])
        to = RUDF::Point.new(x || 0, y || 0) if x || y
      end
      { kind: :goto, page: idx, to: to, uri: nil }
    end

    def resolve_named_destination(name)
      dest = lookup_named_destination(name)
      return { kind: :goto, page: nil, to: nil, uri: nil } if dest.nil?

      # A named destination may resolve to an array or a << /D [...] >> dict.
      dest = @pdf.resolve(dest)
      dest = @pdf.resolve(dest["D"]) if dest.is_a?(Hash)
      dest.is_a?(Array) ? dest_from_array(dest) : { kind: :goto, page: nil, to: nil, uri: nil }
    end

    def lookup_named_destination(name)
      catalog = @pdf.catalog
      # PDF 1.1 style: /Dests dictionary in the catalog.
      dests = @pdf.resolve(catalog["Dests"])
      return dests[name] if dests.is_a?(Hash) && dests.key?(name)

      # PDF 1.2 style: /Names /Dests name tree.
      names = @pdf.resolve(catalog["Names"])
      return nil unless names.is_a?(Hash)

      tree = @pdf.resolve(names["Dests"])
      tree.is_a?(Hash) ? search_name_tree(tree, name) : nil
    end

    def search_name_tree(node, target)
      names = @pdf.resolve(node["Names"])
      if names.is_a?(Array)
        names.each_slice(2) do |key, value|
          return value if @pdf.resolve(key) == target
        end
      end

      kids = @pdf.resolve(node["Kids"])
      if kids.is_a?(Array)
        kids.each do |kid|
          result = search_name_tree(@pdf.resolve(kid), target)
          return result if result
        end
      end
      nil
    end

    def file_spec(spec)
      spec = @pdf.resolve(spec)
      case spec
      when String then spec.b.force_encoding("UTF-8")
      when Hash
        f = @pdf.resolve(spec["F"]) || @pdf.resolve(spec["UF"])
        f.is_a?(String) ? f.b.force_encoding("UTF-8") : nil
      end
    end

    def numeric(value)
      value = @pdf.resolve(value)
      value.is_a?(Numeric) ? value.to_f : nil
    end
  end
end
