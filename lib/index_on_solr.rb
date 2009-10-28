module IndexOnSolr  
  def self.included(base)  
    base.extend(ClassMethods)  
  end  

  module ClassMethods  
    def index_on_solr(options = {})
      if_condition     ||= options.delete(:if)
      unless_condition ||= options.delete(:unless)
      
      cattr_accessor :solr_facet_query
      self.solr_facet_query ||= options.delete(:facet_query)
      
      cattr_accessor :solr_facet_fields
      self.solr_facet_fields ||= options.delete(:facet_fields)
      
      cattr_accessor :solr_core
      self.solr_core ||= options.delete(:core)
      
      cattr_accessor :solr_update_on_change
      self.solr_update_on_change ||= options.delete(:update_on_change)
      
      cattr_accessor :solr_use_live_field
      self.solr_use_live_field = options.delete(:use_live_field).nil? ? true : options.delete(:use_live_field)
      
      cattr_accessor :solr_options
      self.solr_options = options
      
      cattr_accessor :solr_conditions
      self.solr_conditions = { :if => if_condition, :unless => unless_condition }
      
      send("before_update", "has_fields_been_updated") 
      
      send("after_commit_on_create", "create_solr_entry")
      send("after_commit_on_update", "update_solr_entry")
      send("after_commit_on_destroy", "destroy_solr_entry")
      
      send("attr_accessible", "need_solr_update") 
      send("attr_accessor", "need_solr_update") 
            
      extend ClassMethods
      include InstanceMethods
    end 
    
    module InstanceMethods
      
      def create_or_update_entry?
        options = self.solr_conditions
        
        if options[:if].nil?
          if_condition = true
        elsif options[:if].is_a?(Proc)
          if_condition = options[:if].call(self)
        else
          if_condition = self.send(options[:if].to_s)
        end
      
        if options[:unless].nil?
          unless_condition = false
        elsif options[:unless].is_a?(Proc)
          unless_condition = options[:unless].call(self)
        else
          unless_condition = self.send(options[:unless].to_s)
        end
        
        if if_condition && !unless_condition && (self.solr_use_live_field ? self.live.to_s.match(/(true|1)$/i).present? : true) 
          if self.need_solr_update
            return true
          else
            return false
          end
        else
          self.destroy_solr_entry
          return false
        end
      end
    
      def create_solr_entry
        self.need_solr_update = true
        
        if self.create_or_update_entry?
          SOLR_LOG.info "#{Time.now} - Create Solr Entry #{self.id} for model #{self.class.to_s}"   
          conn = self.class.solr_connection
          conn.add(self.solr_entry_fields)
        end
      end
    
      def update_solr_entry(options = {})      
        options[:force] ||= false
        
        self.need_solr_update = true if options[:force]
        
        if self.create_or_update_entry?
          SOLR_LOG.info "#{Time.now} - Update Solr Entry #{self.id} for model #{self.class.to_s}"   
          conn = self.class.solr_connection
          conn.update(self.solr_entry_fields)
          self.need_solr_update = false
          return true
        else
          return false
        end
      end
      
      def solr_entry_fields
        default_fields = {
          :id => self.solr_id, 
          :pk => self.id, 
          :model => self.class.to_s
        }
      
        default_fields[:live_b] = self.live.to_s.match(/(true|1)$/i).present? if self.class.solr_use_live_field?
      
        if self.class.solr_options.present?
          self.class.solr_options.each do |field, value|
            default_fields[field.to_sym] = self.send(value)
          end
        end
      
        default_fields
      end
      
      def has_fields_been_updated
        return unless self.need_solr_update.nil?
        
        self.need_solr_update = true and return unless self.solr_update_on_change.present?
        
        solr_update_on_change.each do |option|
          self.need_solr_update = true if self.send("#{option.to_s}_changed?")
        end
      end
      
      def destroy_solr_entry
        SOLR_LOG.info "#{Time.now} - Destroy Solr Entry #{self.id} for model #{self.class.to_s}"   
        conn = self.class.solr_connection
        conn.delete(self.solr_id)
      end
   
      def solr_id
        "#{self.class.to_s}:#{self.id.to_s}"
      end
      
    end
    
    module ClassMethods
      
      def solr_use_live_field?
        self.solr_use_live_field && self.respond_to?("live")
      end
      
      def solr_connection(options = {})
        SolrToolbox::Tools.connection(:core => self.solr_core)
      end
      
      def solr_search(query, options = {})
        options[:extra_url] ||= ""
        options[:extra_url]  += self.solr_use_live_field? ? "&fq=live_b:true" : ""
        options[:model]       = self.to_s
        options[:core]        = [self.solr_core]
        options[:return]    ||= [:results]
        
        SolrToolbox::Search.query(query, options)
      end

      def solr_facets(options = {})
        options[:return]       = [:facets]
        options[:facet_query]  = self.solr_facet_query  || []
        options[:facet_fields] = self.solr_facet_fields || []
        
        self.solr_search("", options)[:facets]
      end
    
      def solr_pagination(query, options = {})
        SolrToolbox::Search.paginate(self.solr_search(query, options))
      end
    
      def rebuild_solr_index(options = {})
        SolrToolbox::Tools.create_solr_index(self, options = {})
      end
      
      def create_solr_index(options = {})
        SolrToolbox::Tools.create_solr_index(self, options = {})
      end
      
      def update_solr_index(options = {})
        SolrToolbox::Tools.update_solr_index(self, options = {})
      end
      
      def verify_solr_index_integrity(options = {})
        options[:fix] = true unless options[:fix].present?
        SolrToolbox::Tools.verify_solr_index_integrity(self, options = {})
      end
      
    end
    
  end  
end