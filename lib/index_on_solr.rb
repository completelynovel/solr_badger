module IndexOnSolr  
  def self.included(base)  
    base.extend(ClassMethods)  
  end  

  module ClassMethods  
    def index_on_solr(options = {})
      update_on_change ||= options.delete(:update_on_change)
      if_condition     ||= options.delete(:if)
      unless_condition ||= options.delete(:unless)
      core             ||= options.delete(:core)
      use_live_field     = options.delete(:use_live_field).nil? ? true : options.delete(:use_live_field)
      facet_fields     ||= options.delete(:facet_fields)
      facet_query     ||= options.delete(:facet_query)
      
      send("after_commit_on_create", "create_solr_entry")
      send("after_commit_on_update", "update_solr_entry")
      send("after_commit_on_destroy", "destroy_solr_entry")
      
      send("before_update", "has_fields_been_updated") 
      
      send("attr_accessible", "need_solr_update") 
      send("attr_accessor", "need_solr_update") 
      
      # Method : has_fields_been_updated
      method = %{ 
        def has_fields_been_updated
      }
      
      if update_on_change.present?
        method << %{
          ["#{update_on_change.join('", "')}"].each { |option| self.need_solr_update = true if self.send(option +"_changed?") }
        }
      else
        method << %{    
          self.need_solr_update = true
        }
      end
      method << %{ 
        end
      }
      class_eval method
      
      # Method : create_solr_entry
      method = %{
        def create_solr_entry
      }
      
      method << %{
          unless #{if_condition}
            return
          end
      } if if_condition.present?
      
      method << %{
          if #{unless_condition}
            return
          end
      } if unless_condition.present?
      
      method << %{          
          conn = #{self.to_s}.solr_connection
          conn.add(self.solr_entry_fields)
        end
      }
      class_eval method 
      
      # Method : update_solr_entry
      method = %{
        def update_solr_entry(options = {})
      }

      method << %{
          unless #{if_condition}
            self.destroy_solr_entry
            false
          end
      } if if_condition.present?

      method << %{
          if #{unless_condition}
            self.destroy_solr_entry
            false
          end
      } if unless_condition.present?

      method << %{          
          options[:force] ||= false
          
          if self.need_solr_update || options[:force]
            conn = #{self.to_s}.solr_connection
            conn.update(self.solr_entry_fields)
            self.need_solr_update = false
            true
          else
            false
          end
        end
      }
      class_eval method 
      
      # Method : destroy_solr_entry
      method = %{
        def destroy_solr_entry
          conn = #{self.to_s}.solr_connection
          conn.delete(self.solr_id)
        end
      }
      class_eval method

      # Method : solr_id        
      method = %{
        def solr_id
          "#{self.to_s}:"+ self.id.to_s
        end
      }
      class_eval method
     
      # Method : solr_entry_fields
      method = %{
        def solr_entry_fields
          default_fields = {
            :id => self.solr_id, 
            :pk => self.id, 
            :model => self.class.to_s
          }
          #{"default_fields[:live_b] = self.live if self.respond_to?(\"live\")" if use_live_field}
      }
      options.each do |field, value|
        method << %{
          default_fields[:#{field}] = self.send("#{value}")
        }
      end
      method << %{
          default_fields
        end
      }
      class_eval method
      
      method = %{
        def self.solr_connection(options = {})
          SolrToolbox::Tools.connection(:core => "#{core}")
        end
      }
      class_eval method
      
      method = %{
        def self.solr_search(query, options = {})
          options[:extra_url] ||= ""
          #{"options[:extra_url] += self.respond_to?(\"live\") ? \"&fq=live_b:true\" : \"\"" if use_live_field}  # By default we only want 'live' items
          options[:model]       = "#{self.to_s}"
          options[:core]        = [:#{core}]
          options[:return]    ||= [:results]
          
          SolrToolbox::Search.query(query, options)
        end
      }
      class_eval method
      
      if facet_fields.present? || facet_query.present?
        method = %{
          def self.solr_facets(options = {})
            options[:return]         = [:facets]
            options[:facet_query]  ||= []
            options[:facet_fields] ||= []
        }
        
        facet_query.each do |facet|
          method << %{
            options[:facet_query].push("#{facet.to_s}")
          }
        end if facet_query.present?
        
        facet_fields.each do |facet|
          method << %{
            facet = { #{facet.collect { |k, v| ":#{k.to_s} => \"#{v.to_s}\"" }.join(", ")} }
            options[:facet_fields].push(facet) 
          }
        end if facet_fields.present?
        
        method << %{
            self.solr_search("", options)[:facets]
          end
        }
        class_eval method
      end
      
      method = %{
        def self.solr_pagination(query, options = {})
          SolrToolbox::Search.paginate(#{self.to_s}.solr_search(query, options))
        end
      }
      class_eval method
      
      method = %{
        def self.rebuild_solr_index(options = {})
          SolrToolbox::Tools.create_solr_index(#{self.to_s}, options = {})
        end
        def self.create_solr_index(options = {})
          SolrToolbox::Tools.create_solr_index(#{self.to_s}, options = {})
        end
        def self.update_solr_index(options = {})
          SolrToolbox::Tools.update_solr_index(#{self.to_s}, options = {})
        end
      }
      class_eval method
    end  
  end  
end