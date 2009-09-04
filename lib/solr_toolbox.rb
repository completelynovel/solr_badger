require 'logger'

module SolrToolbox
  
  class Search
    
    def self.global(query, options = {})
      # Example : SolrToolbox::Search.global("anna lewis", :core => [:listings, :others])
      options[:core]   ||= SOLR_CONFIG["cores"].keys
      options[:return] ||= []
      options[:return]  |= [:results]
      search             = SolrToolbox::Search.query(query, options)
      
      SolrToolbox::Search.paginate(search)
    end
    
    def self.query(query, options = {})
      require 'open-uri'
      
      options[:extra_query]   ||= ""
      options[:page]          ||= 1
      options[:per_page]      ||= 10
      options[:solr_page]     ||= options[:page].to_i * options[:per_page].to_i - options[:per_page].to_i
      options[:sort]          ||= ""
      options[:facets]        ||= []
      options[:core]          ||= ""
      options[:extra_url]     ||= ""
      options[:fl]            ||= "id" # We only need the id field
      options[:dismax]        ||= false
      options[:return]        ||= []
      options[:facets_query]  ||= []
      options[:facets_fields] ||= []
      options[:model]         ||= ""
      
      # Encode current query
      allow_fields_in_query = options.delete(:allow_fields_in_query) || false
      query = SolrToolbox::Tools.encode_query(query, allow_fields_in_query)
      
      # Query Solr to get the results according to the current page
      url  = SolrToolbox::Tools.core_url(options[:core][0], :select => true)
      
      if options[:extra_query].present?
        url << URI.encode("?q={!boost b=\"#{options[:extra_query]}\" v=$qq}")
        url << "&qq=#{query}"
      else
        url << "?q=#{query}" 
      end
      
      url << "&qt=dismax" if options[:dismax] && !SolrToolbox::Tools.empty_query?(query)
      url << "&rows=#{options[:per_page].to_s}" 
      url << "&start=#{options[:solr_page].to_s}" 
      url << "&sort=#{options[:sort]}" if options[:sort].present?
      url << "&shards="+ options[:core].collect{|core| SolrToolbox::Tools.core_url(core, :http => false)}.join(",") if options[:core].size > 1
      url << "&fl=#{options[:fl]}" if options[:fl].present?
      url << "&fq=model:#{options[:model].to_s}" if options[:model].present? 
      
      options[:facets].each{|f| url << "&fq=#{URI.encode(f).gsub("&", "%26")}"} unless options[:facets].empty?
      
      if options[:facet_query].present? || options[:facet_fields].present?
        url << "&facet=true"
        # Custom query, to get only one status, ex : &facet.query=live_b:true
        url << "&facet.query=#{options[:facet_query].join("&facet.query=")}" if options[:facet_query].present?
        # Fields query
        options[:facet_fields].each do |facet|
          facet[:field]    ||= ""
          facet[:limit]    ||= -1
          facet[:mincount] ||= 0
          facet[:sort]     ||= true # true (by number), false (by name)
          
          url << "&facet.field=#{facet[:field].to_s}"
          url << "&f.#{facet[:field].to_s}.facet.limit=#{facet[:limit].to_s}"
          url << "&f.#{facet[:field].to_s}.facet.mincount=#{facet[:mincount].to_s}"
          url << "&f.#{facet[:field].to_s}.facet.sort=#{facet[:sort].to_s}"
        end if options[:facet_fields].present? 
      end
      
      url << options[:extra_url]
      url << SOLR_CONFIG["extra_url"] if SOLR_CONFIG["extra_url"].present?
      
      # Search url
      RAILS_DEFAULT_LOGGER.info "Search on Solr with : "+ url
      xml = open(url) { |f| Hpricot.XML(f) }
      
      # Get the informations of the XML fetched by solr 
      solr_ids = xml.search("//str[@name='id']").collect { |entry| entry.inner_html }
      ids      = solr_ids.collect { |id| id.split(":")[1] }
      found    = xml.search("//result").collect { |r| r.attributes["numFound"] }.first
      
      # Return list of ids and results founds 
      search = { 
        :solr_ids => solr_ids,
        :ids => ids,
        :found => found, 
        :page => options[:page], 
        :per_page => options[:per_page]
      }
      
      # Search for results
      if options[:return].include?(:results)
        # Only one model
        if options[:model].present?
          results_options = {
            :conditions => { :id => ids },
            :order => SolrToolbox::Tools.keep_ids_order(ids)
          }
          search[:results] = ids.present? ? options[:model].constantize.all(results_options) : []
        # One different model per id
        else
          search[:results] = solr_ids.present? ? solr_ids.collect { |id| id.split(":")[0].constantize.find(id.split(":")[1]) } : []
        end
      end
      
      search[:req]    = url if options[:return].include?(:req)
      search[:facets] = SolrToolbox::Tools.xml_to_hash(xml.search("//lst[@name='facet_counts']/")) if options[:return].include?(:facets)
      
      search
    end
    
    def self.paginate(search)
      WillPaginate::Collection.create(search[:page], search[:per_page], search[:found]) do |pager|
        pager.replace search[:results]
      end
    end
  end
  
  class Tools
    
    def self.encode_query(query, allow_fields_in_query = false)
      query = SolrToolbox::Tools.empty_query(query)
      query = query.gsub(/([~!<>="*\(\)\[\]])/, '\\\1')
      
      if allow_fields_in_query
        query = query.empty? ? "*:*" : URI.encode(query).gsub("&", "%26")
      else
        query = query.empty? ? "*:*" : URI.encode(query.gsub(/:/) {|c| '/\\'+ c}).gsub("&", "%26")
      end
      
      query
    end
    
    def self.empty_query(query)
      query = "" if SolrToolbox::Tools.empty_query?(query)
      query = query.strip
      query
    end
    
    def self.empty_query?(query)
      query.nil? || query == "" || query == "*:*"
    end
    
    def self.connection(options = {})
      require 'solr'
      
      options[:core]       ||= ""
      options[:autocommit] ||= :on
      
      Solr::Connection.new(SolrToolbox::Tools.core_url(options[:core]), :autocommit => options[:autocommit])
    end
    
    def self.core_url(core, options = {})
      options[:http]   = true  if options[:http].nil?
      options[:select] = false if options[:select].nil?
      
      url  = ""
      url << "http://" if options[:http]
      url << SOLR_CONFIG["cores"][core.to_s]
      url << "/select/" if options[:select]
      url
    end
    
    def self.update_solr_index(model, options = {})
      options[:limit] ||= 0
      
      entries = options[:limit] == 0 ? model.all : model.all(:limit => options[:limit]) 
      
      RAILS_DEFAULT_LOGGER.info "Update Solr index for the #{model.to_s} model (#{entries.size} entries)..."
      
      entries.each do |entry|
        RAILS_DEFAULT_LOGGER.info "Update entry "+ entry.id.to_s
        entry.update_solr_entry(:force => true)
      end
    end
    
    def self.create_solr_index(model, options = {})
      options[:limit] ||= 0
      
      entries = options[:limit] == 0 ? model.all : model.all(:limit => options[:limit]) 
      
      RAILS_DEFAULT_LOGGER.info "Create Solr index for the #{model.to_s} model (#{entries.size} entries)..."
      
      entries.each do |entry|
        RAILS_DEFAULT_LOGGER.info "Create entry "+ entry.id.to_s
        entry.create_solr_entry
      end
    end
    
    def self.verify_solr_index_integrity(model, options = {})
      # SolrToolbox::Tools.verify_solr_index_integrity(Person, :core => :others)
      options[:fix]  ||= false
      options[:core] ||= ""
      
      ids = model.all(:select => "id").collect(&:id)
      useless_ids = (ids.first..ids.last).to_a - ids

      if options[:fix]
        useless_ids.each do |id|
          conn = SolrToolbox::Tools.connection(options)
          conn.delete("#{model.to_s}:#{id}")
        end
      end

      useless_ids
    end
    
    def self.search_sentence(query, will_paginate_collection)
      page         = will_paginate_collection.current_page
      per_page     = will_paginate_collection.per_page
      found        = will_paginate_collection.total_entries
      first_result = (page * per_page) - per_page
      last_result  = first_result + per_page
      last_result  = found if last_result > found
      first_result = first_result + 1
      
      if found > 0
        sentence = [
          "Results",
          "#{first_result.to_s}-#{last_result.to_s}",
          "of",
          "<strong>#{found.to_s}</strong>",
          "for the term",
          "<strong>#{query}</strong>"
        ].join(" ")
      else
        "We did not find any results for <strong>#{query}</strong>"
      end
    end
    
    def self.keep_ids_order(ids)
      ids.present? ? "FIELD(id, '"+ ids.join("', '") +"')" : ""
    end
  
    def self.xml_to_hash(xml)
      h = {}
      xml.each do |node|
        node.is_a?(Hpricot::Elem) ? h[node.attributes["name"]] = SolrToolbox::Tools.xml_to_hash(node.search("/")) : h = node
      end
      h
    end
    
  end
  
end